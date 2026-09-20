import Foundation

struct CurrentTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let startedAt: Date
    var completedAt: Date?
    var updatedAt: Date

    init(title: String, now: Date = Date()) {
        id = UUID()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        startedAt = now
        updatedAt = now
    }
}
