import Foundation

protocol EngagementClock {
    var now: TimeInterval { get }
}

struct SystemEngagementClock: EngagementClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Deterministic inference with frozen idle counters and one retreat per grace interval.
final class EngagementEngine {
    private let clock: EngagementClock
    let configuration: EngagementConfiguration
    private var previousTick: TimeInterval?
    private var lastActivity: TimeInterval?
    private var resetAt: TimeInterval
    private(set) var continuousActiveDuration: TimeInterval = 0
    private(set) var state: FlowState = .idle
    private(set) var confidence: Double = 0
    private(set) var isIdle = true
    private(set) var isTakingBreak = false
    private var idleOrigin: FlowState?
    private(set) var achievement = false
    private(set) var achievementReason: String?
    private(set) var sessionID: UUID?
    private(set) var creditedThisTick: TimeInterval = 0

    init(configuration: EngagementConfiguration = .production,
         clock: EngagementClock = SystemEngagementClock()) {
        self.configuration = configuration
        self.clock = clock
        resetAt = clock.now
    }

    func reset() {
        previousTick = nil
        lastActivity = nil
        resetAt = clock.now
        continuousActiveDuration = 0
        state = .idle
        confidence = 0
        isIdle = true
        isTakingBreak = false
        idleOrigin = nil
        sessionID = nil
        clearTick()
    }

    private func clearTick() {
        achievement = false
        achievementReason = nil
        creditedThisTick = 0
    }

    private func enterIdle() {
        guard !isIdle else { return }
        idleOrigin = state
        isIdle = true
        sessionID = nil
        confidence = 0.25
        switch state {
        case .engaged: state = .returning
        case .returning, .idle: state = .idle
        }
    }

    func tick(activityAge: TimeInterval) {
        clearTick()
        let now = clock.now
        let elapsed = max(0, now - (previousTick ?? now))
        let grace = max(1, configuration.idleGrace)
        // No duration is inferred for a suspended sampling loop.
        let samplingGap = elapsed >= max(5, grace)
        if samplingGap { enterIdle() }
        let priorActivity = lastActivity
        if activityAge.isFinite && activityAge >= 0 {
            let candidate = now - activityAge
            if candidate >= resetAt {
                lastActivity = max(lastActivity ?? candidate, candidate)
            }
        }
        defer { previousTick = now }
        guard let lastActivity else { return }
        // Detect a grace expiry followed by new input between adjacent samples.
        if let priorActivity, elapsed < grace, lastActivity - priorActivity >= grace {
            if !isIdle, !samplingGap, let previousTick {
                creditedThisTick = max(0, min(now, priorActivity + grace) - max(previousTick, resetAt))
                continuousActiveDuration += creditedThisTick
            }
            enterIdle()
        }
        let inactivity = max(0, now - lastActivity)
        let before = continuousActiveDuration
        if !isIdle, !samplingGap, let previousTick {
            let end = min(now, lastActivity + grace)
            creditedThisTick = max(0, end - max(previousTick, resetAt))
            continuousActiveDuration += creditedThisTick
        }
        if inactivity >= grace {
            enterIdle()
            let steps = inactivity / grace
            switch idleOrigin ?? .idle {
            case .engaged:
                state = steps >= 2 ? .idle : .returning
                isTakingBreak = steps >= 3
            case .returning:
                state = .idle
                isTakingBreak = steps >= 2
            case .idle:
                state = .idle
                isTakingBreak = true
            }
            return
        }
        if isIdle {
            isIdle = false
            isTakingBreak = false
            idleOrigin = nil
            sessionID = UUID()
        }
        confidence = 1
        let nextState: FlowState = continuousActiveDuration >= configuration.engagedAfter ? .engaged : .returning
        let crossedGreen = state != .engaged && nextState == .engaged
        state = nextState
        var checkpoint = false
        if let interval = configuration.checkpointInterval, interval.isFinite, interval > 0 {
            checkpoint = floor(continuousActiveDuration / interval) > floor(before / interval)
        }
        achievement = crossedGreen || checkpoint
        if crossedGreen && checkpoint { achievementReason = "green_and_checkpoint" }
        else if crossedGreen { achievementReason = "green" }
        else if checkpoint { achievementReason = "checkpoint" }
    }
}
