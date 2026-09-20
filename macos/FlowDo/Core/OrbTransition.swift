import Foundation

/// Immutable endpoints prevent a finished swirl from falling back to an old red source.
struct OrbTransition: Equatable {
    static let duration: TimeInterval = 3
    let from: FlowState
    let to: FlowState
    let startedAt: TimeInterval

    func progress(at now: TimeInterval) -> Double {
        min(1, max(0, (now - startedAt) / Self.duration))
    }
}
