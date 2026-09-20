protocol TaskStore {
    func loadCurrentTask() async throws -> CurrentTask?
    func save(_ task: CurrentTask) async throws
    func completeCurrentTask() async throws
}
