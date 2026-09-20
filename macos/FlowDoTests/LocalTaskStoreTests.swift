import XCTest
#if canImport(FlowDoCore)
@testable import FlowDoCore
#endif

final class LocalTaskStoreTests: XCTestCase {
    private var directory: URL!
    private var url: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("task.json")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testFreshStoreIsEmpty() async throws {
        let task = try await LocalTaskStore(url: url).loadCurrentTask()
        XCTAssertNil(task)
    }

    func testTaskSurvivesNewStoreInstance() async throws {
        let task = CurrentTask(title: "Prepare TAC slides")
        try await LocalTaskStore(url: url).save(task)
        let restored = try await LocalTaskStore(url: url).loadCurrentTask()
        XCTAssertEqual(restored, task)
    }

    func testChangePreservesIdentityAndOnlyOneTask() async throws {
        let store = LocalTaskStore(url: url)
        var task = CurrentTask(title: "Draft")
        try await store.save(task)
        let id = task.id
        let startedAt = task.startedAt
        task.title = "Prepare slides"
        task.updatedAt = task.updatedAt.addingTimeInterval(1)
        try await store.save(task)
        let restored = try await store.loadCurrentTask()
        XCTAssertEqual(restored?.id, id)
        XCTAssertEqual(restored?.startedAt, startedAt)
        XCTAssertEqual(restored?.title, "Prepare slides")
        XCTAssertEqual(restored?.updatedAt, task.updatedAt)
    }

    func testCompleteThenStartAnotherTask() async throws {
        let store = LocalTaskStore(url: url)
        try await store.save(CurrentTask(title: "First"))
        try await store.completeCurrentTask()
        let restored = try await LocalTaskStore(url: url).loadCurrentTask()
        XCTAssertNil(restored)
        let completed = try JSONDecoder().decode(CurrentTask.self, from: Data(contentsOf: url))
        XCTAssertNotNil(completed.completedAt)
        let next = CurrentTask(title: "Next")
        try await store.save(next)
        let current = try await store.loadCurrentTask()
        XCTAssertEqual(current, next)
    }

    func testCorruptFileIsReportedAndPreserved() async throws {
        let bytes = Data("not json".utf8)
        try bytes.write(to: url)
        do {
            _ = try await LocalTaskStore(url: url).loadCurrentTask()
            XCTFail("Expected decoding error")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testEmptyTitleIsRejected() async throws {
        do {
            try await LocalTaskStore(url: url).save(CurrentTask(title: " \n "))
            XCTFail("Expected validation error")
        } catch LocalTaskStore.StoreError.emptyTitle { }
    }
}
