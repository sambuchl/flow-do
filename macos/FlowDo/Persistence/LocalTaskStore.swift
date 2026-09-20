import Foundation

/// Single task, atomically replaced on disk. No engagement data is written.
actor LocalTaskStore: TaskStore {
    private let url: URL

    init(url: URL) { self.url = url }

    static func applicationStore() throws -> LocalTaskStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("FlowDo", isDirectory: true)
        return LocalTaskStore(url: directory.appendingPathComponent("current-task.json"))
    }

    func loadCurrentTask() async throws -> CurrentTask? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let task = try JSONDecoder().decode(CurrentTask.self, from: Data(contentsOf: url))
        return task.completedAt == nil ? task : nil
    }

    func save(_ task: CurrentTask) async throws {
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.emptyTitle
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(task).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func completeCurrentTask() async throws {
        guard var task = try await loadCurrentTask() else { return }
        let now = Date()
        task.completedAt = now
        task.updatedAt = now
        try await save(task)
    }

    enum StoreError: Error { case emptyTitle }
}
