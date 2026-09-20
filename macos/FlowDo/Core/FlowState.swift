enum FlowState: String, Codable, CaseIterable {
    case idle, returning, engaged

    var label: String {
        switch self {
        case .idle: return "At ease"
        case .returning: return "Returning"
        case .engaged: return "Engaged"
        }
    }
}
