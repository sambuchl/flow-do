import XCTest
#if canImport(FlowDoCore)
@testable import FlowDoCore
#endif

private final class MemoryLog: ActivityLogSink {
    var events: [ActivityLogEvent] = []
    func append(_ event: ActivityLogEvent) { events.append(event) }
}

final class ActivityLoggingTests: XCTestCase {
    func testLoggingIsOffByDefault() {
        let sink = MemoryLog()
        let journal = ActivityJournal(sink: sink)
        let task = CurrentTask(title: "Private task")
        journal.startTask(task, total: 0, reason: "created")
        journal.startSession(task, session: 0, total: 0, reason: "activity")
        journal.note("achievement", task: task, session: 20, total: 20, reason: "green")
        journal.stopSession(task, session: 20, total: 20, reason: "idle")
        journal.stopTask(task, total: 20, reason: "completed")
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testPairsSessionBoundariesAndTaskCompletion() {
        let sink = MemoryLog()
        let journal = ActivityJournal(sink: sink)
        journal.enabled = true
        let task = CurrentTask(title: "Slides")
        journal.startTask(task, total: 0, reason: "created")
        journal.startSession(task, session: 0, total: 0, reason: "activity")
        journal.stopSession(task, session: 30, total: 30, reason: "idle")
        journal.startSession(task, session: 0, total: 30, reason: "activity")
        journal.stopSession(task, session: 10, total: 40, reason: "completed")
        journal.stopTask(task, total: 40, reason: "completed")
        XCTAssertEqual(sink.events.map(\.event), ["task_start", "engagement_start", "engagement_stop",
                                                 "engagement_start", "engagement_stop", "task_stop"])
        XCTAssertEqual(sink.events[0].spanID, sink.events[5].spanID)
        XCTAssertEqual(sink.events[1].spanID, sink.events[2].spanID)
        XCTAssertEqual(sink.events[3].spanID, sink.events[4].spanID)
        XCTAssertNotEqual(sink.events[1].spanID, sink.events[3].spanID)
        XCTAssertEqual(sink.events[2].durationSeconds, 30)
        XCTAssertEqual(sink.events[4].durationSeconds, 10)
        XCTAssertEqual(sink.events[5].durationSeconds, 40)
    }

    func testEnableMidSessionDoesNotBackfillUnobservedDuration() {
        let sink = MemoryLog()
        let journal = ActivityJournal(sink: sink)
        journal.enabled = true
        let task = CurrentTask(title: "Existing")
        journal.startTask(task, total: 200, reason: "logging_enabled")
        journal.startSession(task, session: 50, total: 200, reason: "logging_enabled")
        journal.stopSession(task, session: 65, total: 215, reason: "logging_disabled")
        journal.stopTask(task, total: 215, reason: "logging_disabled")
        journal.enabled = false
        journal.note("achievement", task: task, session: 70, total: 220, reason: "checkpoint")
        XCTAssertEqual(sink.events.count, 4)
        XCTAssertEqual(sink.events[2].durationSeconds, 15)
        XCTAssertEqual(sink.events[3].durationSeconds, 15)
    }

    func testRenamePreservesPairingAndRecordsNewName() {
        let sink = MemoryLog()
        let journal = ActivityJournal(sink: sink)
        journal.enabled = true
        var task = CurrentTask(title: "Before")
        journal.startTask(task, total: 0, reason: "created")
        task.title = "After"
        journal.note("task_renamed", task: task, session: 0, total: 0, reason: "title_changed")
        journal.stopTask(task, total: 0, reason: "completed")
        XCTAssertEqual(sink.events[0].taskID, sink.events[2].taskID)
        XCTAssertEqual(sink.events[0].spanID, sink.events[2].spanID)
        XCTAssertEqual(sink.events[1].taskName, "After")
    }

    func testFileLogIsLazyOrderedAndEscapesTaskText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.jsonl")
        let log = LocalActivityLog(url: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let journal = ActivityJournal(sink: log)
        journal.enabled = true
        let task = CurrentTask(title: "A quoted \"task\"\nsecond line")
        journal.startTask(task, total: 0, reason: "created")
        journal.stopTask(task, total: 15, reason: "app_quit")
        log.flush()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try lines.map { try decoder.decode(ActivityLogEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(events.map(\.event), ["task_start", "task_stop"])
        XCTAssertEqual(events[0].taskName, task.title)
        XCTAssertEqual(events[0].spanID, events[1].spanID)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testAppendAfterInterruptedWriteKeepsNextEventReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.jsonl")
        try Data("partial record".utf8).write(to: url)
        let log = LocalActivityLog(url: url)
        let journal = ActivityJournal(sink: log)
        journal.enabled = true
        journal.startTask(CurrentTask(title: "Recovered"), total: 0, reason: "app_launch")
        log.flush()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(ActivityLogEvent.self, from: Data(lines[1].utf8))
        XCTAssertEqual(event.taskName, "Recovered")
    }

    func testWriteFailureIsReported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let log = LocalActivityLog(url: url.appendingPathComponent("activity.jsonl"))
        let reported = expectation(description: "write error")
        log.onError = { _ in reported.fulfill() }
        let journal = ActivityJournal(sink: log)
        journal.enabled = true
        journal.startTask(CurrentTask(title: "Test"), total: 0, reason: "created")
        log.flush()
        wait(for: [reported], timeout: 1)
    }

    func testTotalSurvivesRestartAndIsIsolatedByTaskID() throws {
        let suite = "FlowDoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let taskID = UUID()
        let first = TaskTimeStore(defaults: defaults)
        XCTAssertEqual(first.load(for: taskID), 0)
        first.save(taskID: taskID, seconds: 125.5)
        let restarted = TaskTimeStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restarted.load(for: taskID), 125.5)
        XCTAssertEqual(restarted.load(for: UUID()), 0)
        restarted.save(taskID: taskID, seconds: .nan)
        XCTAssertEqual(restarted.load(for: taskID), 125.5)
    }
}
