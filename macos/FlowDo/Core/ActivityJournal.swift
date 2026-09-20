import Foundation

struct ActivityLogEvent: Codable {
    let event: String
    let timestamp: Date
    let taskID: UUID
    let taskName: String
    let taskStartedAt: Date
    let spanID: UUID?
    let reason: String
    let sessionSeconds: TimeInterval
    let totalSeconds: TimeInterval
    let durationSeconds: TimeInterval?
}

protocol ActivityLogSink {
    func append(_ event: ActivityLogEvent)
}

/// Boundary-only journal. Matching span IDs pair starts/stops even across renames.
/// Enabling midway begins a new observation window; it never invents past events.
final class ActivityJournal {
    var enabled = false
    private let sink: ActivityLogSink
    private var taskSpan: UUID?
    private var sessionSpan: UUID?
    private var taskBaseline: TimeInterval = 0
    private var sessionBaseline: TimeInterval = 0

    init(sink: ActivityLogSink) { self.sink = sink }

    func startTask(_ task: CurrentTask, total: TimeInterval, reason: String) {
        guard enabled, taskSpan == nil else { return }
        taskSpan = UUID()
        taskBaseline = total
        emit("task_start", task, span: taskSpan, reason: reason, total: total)
    }

    func stopTask(_ task: CurrentTask, total: TimeInterval, reason: String) {
        guard let span = taskSpan else { return }
        emit("task_stop", task, span: span, reason: reason, total: total,
             duration: max(0, total - taskBaseline))
        taskSpan = nil
    }

    func startSession(_ task: CurrentTask, session: TimeInterval, total: TimeInterval, reason: String) {
        guard enabled, sessionSpan == nil else { return }
        sessionSpan = UUID()
        sessionBaseline = session
        emit("engagement_start", task, span: sessionSpan, reason: reason, session: session, total: total)
    }

    func stopSession(_ task: CurrentTask, session: TimeInterval, total: TimeInterval, reason: String) {
        guard let span = sessionSpan else { return }
        emit("engagement_stop", task, span: span, reason: reason, session: session,
             total: total, duration: max(0, session - sessionBaseline))
        sessionSpan = nil
    }

    func note(_ event: String, task: CurrentTask, session: TimeInterval, total: TimeInterval, reason: String) {
        emit(event, task, span: sessionSpan ?? taskSpan, reason: reason, session: session, total: total)
    }

    private func emit(_ event: String, _ task: CurrentTask, span: UUID?, reason: String,
                      session: TimeInterval = 0, total: TimeInterval, duration: TimeInterval? = nil) {
        guard enabled else { return }
        sink.append(ActivityLogEvent(event: event, timestamp: Date(), taskID: task.id,
            taskName: task.title, taskStartedAt: task.startedAt, spanID: span,
            reason: reason, sessionSeconds: session, totalSeconds: total, durationSeconds: duration))
    }
}
