import XCTest
#if canImport(FlowDoCore)
@testable import FlowDoCore
#endif

final class PulseRhythmTests: XCTestCase {
    func testDefaultPulseReturnsToItsColorAfterOneBeat() {
        let beat = 60 / PulseRhythm.defaultBPM
        XCTAssertEqual(PulseRhythm.whiteAmount(at: 0, epoch: 0, bpm: 70), 0, accuracy: 0.000001)
        XCTAssertEqual(PulseRhythm.whiteAmount(at: beat / 2, epoch: 0, bpm: 70), 1, accuracy: 0.000001)
        XCTAssertEqual(PulseRhythm.whiteAmount(at: beat, epoch: 0, bpm: 70), 0, accuracy: 0.000001)
    }

    func testFivePressesUseFourIntervals() {
        var sampler = PulseTapSampler()
        for time in [0.0, 0.5, 1, 1.5] { sampler.record(at: time) }
        XCTAssertNil(sampler.bpm)
        sampler.record(at: 2)
        XCTAssertEqual(sampler.bpm ?? 0, 120, accuracy: 0.000001)
    }

    func testSlidingWindowAveragesOnlyLastFivePresses() {
        var sampler = PulseTapSampler()
        for time in [0.0, 1, 2, 3, 4, 4.5] { sampler.record(at: time) }
        XCTAssertEqual(sampler.timestamps, [1, 2, 3, 4, 4.5])
        XCTAssertEqual(sampler.bpm ?? 0, 60 / 0.875, accuracy: 0.000001)
    }

    func testDuplicateInvalidAndOldTimestampsDoNotCount() {
        var sampler = PulseTapSampler()
        for time in [1.0, 1, 0, .nan, .infinity] { sampler.record(at: time) }
        XCTAssertEqual(sampler.tapCount, 1)
    }

    func testLongBreakStartsCollectionAgain() {
        var sampler = PulseTapSampler()
        for time in [0.0, 1, 2, 3, 4, 10] { sampler.record(at: time) }
        XCTAssertEqual(sampler.timestamps, [10])
        XCTAssertNil(sampler.bpm)
    }

    func testSwirlHasFixedEndpointsAndFinishesInThreeSeconds() {
        let transition = OrbTransition(from: .returning, to: .engaged, startedAt: 100)
        XCTAssertEqual(transition.progress(at: 100), 0)
        XCTAssertEqual(transition.progress(at: 101.5), 0.5)
        XCTAssertEqual(transition.progress(at: 103), 1)
        XCTAssertEqual(transition.progress(at: 500), 1)
        XCTAssertEqual(transition.from, .returning)
        XCTAssertEqual(transition.to, .engaged)
    }
}
