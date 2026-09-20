import Foundation

/// A single aggregate, not a history: replaced when a new task starts.
final class TaskTimeStore {
    private struct Snapshot: Codable {
        let taskID: UUID
        let seconds: TimeInterval
    }
    private let defaults: UserDefaults
    private let key = "currentTaskTime"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func load(for taskID: UUID) -> TimeInterval {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.taskID == taskID, snapshot.seconds.isFinite, snapshot.seconds >= 0 else { return 0 }
        return snapshot.seconds
    }

    func save(taskID: UUID, seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 0,
              let data = try? JSONEncoder().encode(Snapshot(taskID: taskID, seconds: seconds)) else { return }
        defaults.set(data, forKey: key)
    }
}
