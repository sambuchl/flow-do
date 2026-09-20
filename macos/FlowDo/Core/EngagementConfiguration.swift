import Foundation

struct EngagementConfiguration: Codable, Equatable {
    var idleGrace: TimeInterval = 60
    let engagedAfter: TimeInterval
    var checkpointInterval: TimeInterval? = 1_200

    static let production = EngagementConfiguration(engagedAfter: 240)
    // Debug changes the green threshold only; the user's idle grace always applies.
    static let debug = EngagementConfiguration(engagedAfter: 20)
}
