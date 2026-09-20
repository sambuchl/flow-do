import Foundation
import Combine
import AppKit

enum BadgePosition: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeft: return "Top-left"
        case .topRight: return "Top-right"
        case .bottomLeft: return "Bottom-left"
        case .bottomRight: return "Bottom-right"
        }
    }
}

enum CheckpointUnit: String, CaseIterable, Identifiable {
    case seconds, minutes
    var id: String { rawValue }
    var multiplier: Double { self == .minutes ? 60 : 1 }
}

@MainActor
final class FlowDoModel: ObservableObject {
    let music: BackgroundMusic
    @Published private(set) var currentTask: CurrentTask?
    @Published private(set) var state: FlowState = .idle
    @Published private(set) var confidence: Double = 0
    @Published private(set) var paused = false
    @Published private(set) var busy = true
    @Published private(set) var ready = false
    @Published var errorMessage: String?
    @Published private(set) var debugThresholds: Bool
    @Published private(set) var checkpointValue: Int
    @Published private(set) var checkpointUnit: CheckpointUnit
    @Published private(set) var badgeVisible = false
    @Published private(set) var badgePosition: BadgePosition
    @Published private(set) var achievementStartedAt: TimeInterval?
    @Published private(set) var orbTransition: OrbTransition?
    @Published private(set) var completionStartedAt: TimeInterval?
    @Published private(set) var idleGraceSeconds: Int
    @Published private(set) var pulseBPM: Double
    @Published private(set) var pulseEnabled: Bool
    @Published private(set) var countersIdle = false
    @Published private(set) var takingBreak = false
    let pulseEpoch = ProcessInfo.processInfo.systemUptime
    static let completionDuration: TimeInterval = 5.2
    @Published private(set) var sessionTime: TimeInterval = 0
    @Published private(set) var totalTaskTime: TimeInterval = 0
    @Published private(set) var loggingEnabled: Bool
    @Published private(set) var loggingError: String?

    private let store: TaskStore?
    private let defaults: UserDefaults
    private let timeStore: TaskTimeStore
    private let log: LocalActivityLog?
    private let journal: ActivityJournal?
    private var engine: EngagementEngine
    private let input = InputMonitor()
    private var timer: Timer?
    private var observedSessionID: UUID?
    private var lastTimeSave: TimeInterval = 0
    private var persistedTaskID: UUID?
    private var persistedSeconds: TimeInterval = -1
    private var suspensions = Set<String>()
    private var shuttingDown = false

    init(defaults: UserDefaults = .standard) {
        music = BackgroundMusic(defaults: defaults)
        self.defaults = defaults
        timeStore = TaskTimeStore(defaults: defaults)
        let debug = defaults.bool(forKey: "debugThresholds")
        debugThresholds = debug
        let unit = CheckpointUnit(rawValue: defaults.string(forKey: "checkpointUnit") ?? "minutes") ?? .minutes
        // Migrate the previous list to its first checkpoint as a repeating interval.
        let legacyValues = defaults.array(forKey: "checkpointMinutes") as? [Int]
        let legacy = legacyValues.map { $0.first ?? 0 } ?? 20
        let saved = (defaults.object(forKey: "checkpointValue") as? Int) ?? legacy
        let value = min(86_400, max(0, saved))
        checkpointValue = value
        checkpointUnit = unit
        badgePosition = BadgePosition(rawValue: defaults.string(forKey: "badgePosition") ?? "bottomRight") ?? .bottomRight
        let savedGrace = (defaults.object(forKey: "idleGraceSeconds") as? Int) ?? 60
        let grace = min(3600, max(1, savedGrace))
        idleGraceSeconds = grace
        let savedBPM = (defaults.object(forKey: "pulseBPM") as? Double) ?? PulseRhythm.defaultBPM
        pulseBPM = savedBPM.isFinite && PulseRhythm.supportedBPM.contains(savedBPM) ? savedBPM : PulseRhythm.defaultBPM
        pulseEnabled = (defaults.object(forKey: "pulseEnabled") as? Bool) ?? true
        var configuration: EngagementConfiguration = debug ? .debug : .production
        configuration.idleGrace = Double(grace)
        configuration.checkpointInterval = value > 0 ? Double(value) * unit.multiplier : nil
        engine = EngagementEngine(configuration: configuration)
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("FlowDo/Logs/activity.jsonl")
        let activityLog = url.map { LocalActivityLog(url: $0) }
        log = activityLog
        let activityJournal = activityLog.map { ActivityJournal(sink: $0) }
        journal = activityJournal
        let enabled = defaults.bool(forKey: "activityLoggingEnabled") && activityLog != nil
        loggingEnabled = enabled
        activityJournal?.enabled = enabled
        do { store = try LocalTaskStore.applicationStore() }
        catch { store = nil; errorMessage = "FlowDo could not open local storage. Quit and try again." }
        activityLog?.onError = { [weak self] message in
            Task { @MainActor [weak self] in self?.loggingError = message }
        }
        Task { await restore() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer?.tolerance = 0.2
    }

    func restore() async {
        busy = true
        defer { busy = false }
        guard let store else { return }
        do {
            currentTask = try await store.loadCurrentTask()
            if let task = currentTask {
                totalTaskTime = timeStore.load(for: task.id)
                journal?.startTask(task, total: totalTaskTime, reason: "app_launch")
            }
            restoreBadgeVisibility()
            ready = true
            errorMessage = nil
        } catch {
            ready = false
            errorMessage = "Your saved task could not be read. It has been preserved. Retry or check the local file."
        }
    }

    func save(title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !busy, !title.isEmpty, let store else { return }
        tick()
        busy = true
        defer { busy = false }
        let isNew = currentTask == nil
        var task = currentTask ?? CurrentTask(title: title)
        task.title = title
        task.updatedAt = Date()
        do {
            try await store.save(task)
            currentTask = task
            errorMessage = nil
            if isNew {
                totalTaskTime = 0
                resetEngagement(reason: "new_task")
                restoreBadgeVisibility()
                journal?.startTask(task, total: 0, reason: "created")
            } else {
                journal?.note("task_renamed", task: task, session: sessionTime, total: totalTaskTime, reason: "title_changed")
            }
            persistTime()
        } catch { errorMessage = "Your task could not be saved. Please try again." }
    }

    func complete() async {
        guard ready, !busy, let store, let task = currentTask else { return }
        tick()
        busy = true
        defer { busy = false }
        do {
            try await store.completeCurrentTask()
            resetEngagement(reason: "completed")
            journal?.stopTask(task, total: totalTaskTime, reason: "completed")
            currentTask = nil
            totalTaskTime = 0
            badgeVisible = false
            completionStartedAt = ProcessInfo.processInfo.systemUptime
            errorMessage = nil
        } catch { errorMessage = "Your task could not be completed. Please try again." }
    }

    func togglePause() {
        if !paused { tick() }
        paused.toggle()
        music.setSuspended(paused || !suspensions.isEmpty)
        resetEngagement(reason: paused ? "paused" : "resumed")
    }

    func setDebugThresholds(_ enabled: Bool) {
        resetEngagement(reason: "thresholds_changed")
        debugThresholds = enabled
        defaults.set(enabled, forKey: "debugThresholds")
        rebuildEngine()
    }

    func setCheckpoint(value: Int, unit: CheckpointUnit) {
        guard (0...86_400).contains(value) else { return }
        resetEngagement(reason: "checkpoints_changed")
        checkpointValue = value
        checkpointUnit = unit
        defaults.set(value, forKey: "checkpointValue")
        defaults.set(unit.rawValue, forKey: "checkpointUnit")
        rebuildEngine()
    }

    private func rebuildEngine() {
        var configuration: EngagementConfiguration = debugThresholds ? .debug : .production
        configuration.idleGrace = Double(idleGraceSeconds)
        configuration.checkpointInterval = checkpointValue > 0 ? Double(checkpointValue) * checkpointUnit.multiplier : nil
        engine = EngagementEngine(configuration: configuration)
    }

    func setIdleGrace(seconds: Int) {
        guard (1...3600).contains(seconds) else { return }
        resetEngagement(reason: "idle_grace_changed")
        idleGraceSeconds = seconds
        defaults.set(seconds, forKey: "idleGraceSeconds")
        rebuildEngine()
    }

    func setPulse(bpm: Double) {
        guard bpm.isFinite, PulseRhythm.supportedBPM.contains(bpm) else { return }
        pulseBPM = bpm
        defaults.set(bpm, forKey: "pulseBPM")
    }

    func setPulseEnabled(_ enabled: Bool) {
        pulseEnabled = enabled
        defaults.set(enabled, forKey: "pulseEnabled")
    }

    private func changeState(to next: FlowState, animate: Bool = true) {
        let previous = state
        state = next
        if previous != next && animate {
            orbTransition = OrbTransition(from: previous, to: next,
                                          startedAt: ProcessInfo.processInfo.systemUptime)
        } else if !animate { orbTransition = nil }
    }

    func setBadgePosition(_ position: BadgePosition) {
        badgePosition = position
        defaults.set(position.rawValue, forKey: "badgePosition")
    }

    func showBadge() {
        guard currentTask != nil else { return }
        defaults.removeObject(forKey: "dismissedBadgeTaskID")
        badgeVisible = true
    }

    func hideBadge() {
        if let task = currentTask { defaults.set(task.id.uuidString, forKey: "dismissedBadgeTaskID") }
        badgeVisible = false
    }

    private func restoreBadgeVisibility() {
        badgeVisible = currentTask.map {
            defaults.string(forKey: "dismissedBadgeTaskID") != $0.id.uuidString
        } ?? false
    }

    func setLoggingEnabled(_ enabled: Bool) {
        guard enabled != loggingEnabled else { return }
        guard journal != nil else { loggingError = "Local log storage is unavailable."; return }
        tick()
        if !enabled, let task = currentTask {
            journal?.stopSession(task, session: sessionTime, total: totalTaskTime, reason: "logging_disabled")
            journal?.stopTask(task, total: totalTaskTime, reason: "logging_disabled")
        }
        journal?.enabled = enabled
        loggingEnabled = enabled
        defaults.set(enabled, forKey: "activityLoggingEnabled")
        loggingError = nil
        if enabled, let task = currentTask {
            journal?.startTask(task, total: totalTaskTime, reason: "logging_enabled")
            if observedSessionID != nil {
                journal?.startSession(task, session: sessionTime, total: totalTaskTime, reason: "logging_enabled")
            }
        }
        if !enabled { log?.flush() }
    }

    func openLogFolder() {
        guard let url = log?.url.deletingLastPathComponent() else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.open(url)
        } catch { loggingError = "The local log folder could not be opened." }
    }

    func suspend(reason: String) {
        suspensions.insert(reason)
        music.setSuspended(true)
        resetEngagement(reason: reason)
    }

    func resume(reason: String) {
        suspensions.remove(reason)
        music.setSuspended(paused || !suspensions.isEmpty)
        resetEngagement(reason: "resumed")
    }

    func resetEngagement(reason: String = "reset") {
        endSession(reason: reason)
        achievementStartedAt = nil
        completionStartedAt = nil
        engine.reset()
        changeState(to: .idle, animate: false)
        countersIdle = false
        takingBreak = false
        confidence = 0
    }

    private func endSession(reason: String) {
        if let task = currentTask {
            journal?.stopSession(task, session: sessionTime, total: totalTaskTime, reason: reason)
        }
        observedSessionID = nil
        sessionTime = 0
        persistTime()
    }

    private func persistTime() {
        guard let task = currentTask else { return }
        if persistedTaskID != task.id || persistedSeconds != totalTaskTime {
            timeStore.save(taskID: task.id, seconds: totalTaskTime)
            persistedTaskID = task.id
            persistedSeconds = totalTaskTime
        }
        lastTimeSave = ProcessInfo.processInfo.systemUptime
    }

    func shutdown() {
        guard !shuttingDown else { return }
        timer?.invalidate()
        tick()
        shuttingDown = true
        music.shutdown()
        resetEngagement(reason: "app_quit")
        if let task = currentTask { journal?.stopTask(task, total: totalTaskTime, reason: "app_quit") }
        log?.flush()
    }

    static func formattedTime(_ seconds: TimeInterval) -> String {
        let seconds = Int(max(0, seconds).rounded(.down))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let start = completionStartedAt, now - start >= Self.completionDuration { completionStartedAt = nil }
        if let transition = orbTransition, transition.progress(at: now) >= 1 { orbTransition = nil }
        if let start = achievementStartedAt, now - start >= 3.2 { achievementStartedAt = nil }
        guard ready, !busy, !shuttingDown, let task = currentTask, !paused, suspensions.isEmpty else { return }
        let previousSessionTime = sessionTime
        engine.tick(activityAge: input.activityAge())
        totalTaskTime += engine.creditedThisTick
        if observedSessionID != engine.sessionID {
            // Automatic idle freezes the session counter; manual resets still clear it.
            let stoppedTime = previousSessionTime + engine.creditedThisTick
            journal?.stopSession(task, session: stoppedTime, total: totalTaskTime,
                                 reason: engine.isIdle ? "idle" : "sampling_gap")
            observedSessionID = engine.sessionID
            if observedSessionID != nil {
                journal?.startSession(task, session: engine.continuousActiveDuration,
                                     total: totalTaskTime, reason: "activity_resumed")
            }
            persistTime()
        }
        sessionTime = engine.continuousActiveDuration
        countersIdle = engine.isIdle
        takingBreak = engine.isTakingBreak
        if engine.isIdle { achievementStartedAt = nil }
        changeState(to: engine.state)
        confidence = engine.confidence
        if engine.achievement {
            // Keep transition achievements in the journal, without a pink/red rim
            // immediately after reaching green. Scheduled checkpoints still glow.
            if engine.achievementReason == "checkpoint" {
                achievementStartedAt = max(now, orbTransition.map { $0.startedAt + OrbTransition.duration } ?? now)
            } else {
                achievementStartedAt = nil
            }
            journal?.note("achievement", task: task, session: sessionTime, total: totalTaskTime,
                          reason: engine.achievementReason ?? "checkpoint")
        }
        if now - lastTimeSave >= 15 { persistTime() }
    }
}
