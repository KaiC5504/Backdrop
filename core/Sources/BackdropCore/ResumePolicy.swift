import Foundation

public enum ResumePolicy {
    /// Below this a saved position is noise: restarting loses nothing.
    public static let minimumResume: TimeInterval = 5
    public static let finishedWindowSeconds: TimeInterval = 5
    public static let finishedWindowFraction: Double = 0.05

    public static func isFinished(position: TimeInterval, duration: TimeInterval) -> Bool {
        guard duration > 0 else { return false }
        let window = max(finishedWindowSeconds, duration * finishedWindowFraction)
        return duration - position <= window
    }

    public static func startTime(savedPosition: TimeInterval?, duration: TimeInterval) -> TimeInterval {
        guard let saved = savedPosition, saved >= minimumResume,
              !isFinished(position: saved, duration: duration) else { return 0 }
        return saved
    }

    /// nil means "forget this video's position".
    public static func positionToStore(position: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        if position < minimumResume { return nil }
        if isFinished(position: position, duration: duration) { return nil }
        return position
    }
}
