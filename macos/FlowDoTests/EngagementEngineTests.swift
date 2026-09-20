import XCTest
#if canImport(FlowDoCore)
@testable import FlowDoCore
#endif

final class FakeClock: EngagementClock {
    var now: TimeInterval = 0
    func advance(_ seconds: TimeInterval) { now += seconds }
}

final class EngagementEngineTests: XCTestCase {
    private var clock: FakeClock!
    private var engine: EngagementEngine!

    override func setUp() {
        clock = FakeClock()
        engine = EngagementEngine(clock: clock)
    }

    private func work(seconds: Int) {
        engine.tick(activityAge: 0)
        for _ in 0..<seconds {
            clock.advance(1)
            engine.tick(activityAge: 0)
        }
    }

    func testFreshLaunchIsIdle() {
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.confidence, 0)
    }

    func testInputBeforeSessionDoesNotStartEngagement() {
        engine.tick(activityAge: 50)
        XCTAssertEqual(engine.state, .idle)
    }

    func testActivityReturnsAndSustainedActivityProgresses() {
        engine.tick(activityAge: 0)
        XCTAssertEqual(engine.state, .returning)
        work(seconds: 239)
        XCTAssertEqual(engine.state, .returning)
        work(seconds: 1)
        XCTAssertEqual(engine.state, .engaged)
        work(seconds: 960)
        XCTAssertEqual(engine.state, .engaged)
        work(seconds: 2400)
        XCTAssertEqual(engine.state, .engaged)
    }

    func testShortPauseRetainsStateAndConfidence() {
        work(seconds: 240)
        clock.advance(15)
        engine.tick(activityAge: 15)
        XCTAssertEqual(engine.state, .engaged)
        XCTAssertEqual(engine.confidence, 1)
    }

    func testDefaultGraceCountsToSixtyThenStepsBackAndFreezes() {
        work(seconds: 240)
        for age in 1...60 {
            clock.advance(1)
            engine.tick(activityAge: Double(age))
        }
        XCTAssertEqual(engine.state, .returning)
        XCTAssertTrue(engine.isIdle)
        XCTAssertNil(engine.sessionID)
        XCTAssertEqual(engine.continuousActiveDuration, 300)
        XCTAssertEqual(engine.creditedThisTick, 1)
        clock.advance(1)
        engine.tick(activityAge: 61)
        XCTAssertEqual(engine.continuousActiveDuration, 300)
        XCTAssertEqual(engine.creditedThisTick, 0)
    }

    func testLongInactivityHoldsOneStepBackAndActivityResumesCounters() {
        work(seconds: 240)
        for age in 1...120 {
            clock.advance(1)
            engine.tick(activityAge: Double(age))
        }
        XCTAssertEqual(engine.state, .returning)
        XCTAssertTrue(engine.isIdle)
        XCTAssertEqual(engine.continuousActiveDuration, 300)
        clock.advance(1)
        engine.tick(activityAge: 0)
        XCTAssertEqual(engine.state, .engaged)
        XCTAssertFalse(engine.isIdle)
        XCTAssertEqual(engine.continuousActiveDuration, 300)
    }

    func testSleepDoesNotEarnEngagement() {
        work(seconds: 240)
        clock.advance(3600)
        engine.tick(activityAge: 0)
        XCTAssertEqual(engine.state, .engaged)
        XCTAssertEqual(engine.continuousActiveDuration, 240)
        XCTAssertEqual(engine.creditedThisTick, 0)
    }

    func testResetDiscardsPreviousEngagement() {
        work(seconds: 240)
        engine.reset()
        XCTAssertEqual(engine.state, .idle)
        clock.advance(10)
        engine.tick(activityAge: 0)
        XCTAssertEqual(engine.state, .returning)
        XCTAssertEqual(engine.continuousActiveDuration, 0)
    }

    func testDebugThresholds() {
        engine = EngagementEngine(configuration: .debug, clock: clock)
        work(seconds: 20)
        XCTAssertEqual(engine.state, .engaged)
        work(seconds: 20)
        XCTAssertEqual(engine.state, .engaged)
        work(seconds: 20)
        XCTAssertEqual(engine.state, .engaged)
    }

    func testInvalidSensorValueDoesNotCreateActivity() {
        engine.tick(activityAge: .infinity)
        engine.tick(activityAge: .nan)
        engine.tick(activityAge: -1)
        XCTAssertEqual(engine.state, .idle)
    }
    func testPinkWhenReachingGreenOnlyOnce() {
        work(seconds: 239)
        XCTAssertFalse(engine.achievement)
        work(seconds: 1)
        XCTAssertTrue(engine.achievement)
        work(seconds: 1)
        XCTAssertFalse(engine.achievement)
    }

    func testCustomCheckpointsFireOnceAndResetWithSession() {
        var configuration = EngagementConfiguration.production
        configuration.checkpointInterval = 10
        engine = EngagementEngine(configuration: configuration, clock: clock)
        work(seconds: 10)
        XCTAssertTrue(engine.achievement)
        work(seconds: 1)
        XCTAssertFalse(engine.achievement)
        work(seconds: 9)
        XCTAssertTrue(engine.achievement)
        engine.reset()
        XCTAssertFalse(engine.achievement)
        work(seconds: 10)
        XCTAssertTrue(engine.achievement)
    }

    func testEmptyCheckpointsStillCelebrateGreen() {
        var configuration = EngagementConfiguration.debug
        configuration.checkpointInterval = nil
        engine = EngagementEngine(configuration: configuration, clock: clock)
        work(seconds: 20)
        XCTAssertTrue(engine.achievement)
        work(seconds: 40)
        XCTAssertFalse(engine.achievement)
    }

    func testSleepDoesNotAwardMissedCheckpoint() {
        var configuration = EngagementConfiguration.production
        configuration.checkpointInterval = 60
        engine = EngagementEngine(configuration: configuration, clock: clock)
        work(seconds: 30)
        clock.advance(3600)
        engine.tick(activityAge: 0)
        XCTAssertFalse(engine.achievement)
    }

    func testRecurringIntervalAtSuccessiveBoundaries() {
        var configuration = EngagementConfiguration.production
        configuration.checkpointInterval = 60
        engine = EngagementEngine(configuration: configuration, clock: clock)
        for _ in 0..<3 {
            work(seconds: 59)
            XCTAssertFalse(engine.achievement)
            work(seconds: 1)
            XCTAssertTrue(engine.achievement)
        }
    }

    func testCreditedTimeAccumulatesAcrossSessionsWithoutCountingLongIdle() {
        var total: TimeInterval = 0
        engine.tick(activityAge: 0)
        let firstSession = engine.sessionID
        for _ in 0..<240 {
            clock.advance(1)
            engine.tick(activityAge: 0)
            total += engine.creditedThisTick
        }
        for age in 1...120 {
            clock.advance(1)
            engine.tick(activityAge: Double(age))
            total += engine.creditedThisTick
        }
        XCTAssertNil(engine.sessionID)
        XCTAssertEqual(total, 300) // 240 working + 60 seconds of idle grace.
        engine.tick(activityAge: 0)
        XCTAssertNotEqual(engine.sessionID, firstSession)
        XCTAssertEqual(engine.creditedThisTick, 0)
        for _ in 0..<10 {
            clock.advance(1)
            engine.tick(activityAge: 0)
            total += engine.creditedThisTick
        }
        XCTAssertEqual(total, 310)
        XCTAssertEqual(engine.continuousActiveDuration, 310)
    }

    func testInvalidCheckpointIntervalDoesNotFire() {
        for interval in [0.0, -1, .infinity, .nan] {
            var configuration = EngagementConfiguration.production
            configuration.checkpointInterval = interval
            engine = EngagementEngine(configuration: configuration, clock: clock)
            work(seconds: 60)
            XCTAssertFalse(engine.achievement)
        }
    }

    func testConfiguredGraceMakesYellowStepToRedOnlyOnce() {
        var configuration = EngagementConfiguration.production
        configuration.idleGrace = 15
        engine = EngagementEngine(configuration: configuration, clock: clock)
        work(seconds: 10)
        for age in 1...100 {
            clock.advance(1)
            engine.tick(activityAge: Double(age))
        }
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(engine.isIdle)
        XCTAssertEqual(engine.continuousActiveDuration, 25)
        XCTAssertEqual(engine.creditedThisTick, 0)
        engine.tick(activityAge: 0)
        XCTAssertEqual(engine.state, .returning)
        XCTAssertEqual(engine.continuousActiveDuration, 25)
    }

    func testNewInputRestartsGraceCountdown() {
        engine.tick(activityAge: 0)
        for age in 1...59 { clock.advance(1); engine.tick(activityAge: Double(age)) }
        clock.advance(1)
        engine.tick(activityAge: 0)
        for age in 1...59 { clock.advance(1); engine.tick(activityAge: Double(age)) }
        XCTAssertFalse(engine.isIdle)
        XCTAssertEqual(engine.continuousActiveDuration, 119)
        clock.advance(1)
        engine.tick(activityAge: 60)
        XCTAssertTrue(engine.isIdle)
        XCTAssertEqual(engine.continuousActiveDuration, 120)
    }

    func testOneSecondGraceStillCreditsSustainedInput() {
        var configuration = EngagementConfiguration.production
        configuration.idleGrace = 1
        engine = EngagementEngine(configuration: configuration, clock: clock)
        work(seconds: 10)
        XCTAssertEqual(engine.continuousActiveDuration, 10)
        XCTAssertFalse(engine.isIdle)
        clock.advance(1)
        engine.tick(activityAge: 1)
        XCTAssertTrue(engine.isIdle)
        XCTAssertEqual(engine.continuousActiveDuration, 11)
    }

}
