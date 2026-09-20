import CoreGraphics

struct InputMonitor {
    /// Only elapsed time is observed, never CGEvent objects or key values.
    func activityAge() -> Double {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: ~UInt32(0))!)
    }
}
