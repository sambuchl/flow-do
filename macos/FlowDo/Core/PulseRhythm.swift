import Foundation

struct PulseRhythm {
    static let defaultBPM: Double = 70
    static let supportedBPM = 30.0...180.0

    static func whiteAmount(at time: TimeInterval, epoch: TimeInterval, bpm: Double) -> Double {
        guard time.isFinite, epoch.isFinite, bpm.isFinite, supportedBPM.contains(bpm) else { return 0 }
        let beats = max(0, time - epoch) * bpm / 60
        let phase = beats.truncatingRemainder(dividingBy: 1)
        // Smoothly lift the current color to white and return, without a hard flash.
        return (1 - cos(phase * 2 * .pi)) / 2
    }
}

/// Five press timestamps give four intervals; only this rolling window is retained.
struct PulseTapSampler {
    private(set) var timestamps: [TimeInterval] = []
    private(set) var tapCount = 0

    mutating func record(at time: TimeInterval) {
        guard time.isFinite else { return }
        if let last = timestamps.last {
            guard time > last else { return }
            if time - last > 5 { timestamps.removeAll(); tapCount = 0 }
        }
        timestamps.append(time)
        if timestamps.count > 5 { timestamps.removeFirst() }
        tapCount += 1
    }

    var bpm: Double? {
        guard timestamps.count == 5, let first = timestamps.first, let last = timestamps.last else { return nil }
        return 60 / ((last - first) / 4)
    }
}
