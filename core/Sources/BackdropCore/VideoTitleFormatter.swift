import Foundation

/// Photos videos carry no meaningful name, so a video is named by when it was shot.
/// A class so the DateFormatter is built once; DateFormatter is safe to share for
/// formatting.
public final class VideoTitleFormatter: @unchecked Sendable {
    private let dateFormatter: DateFormatter

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE d MMM yyyy, HH:mm"
        dateFormatter = formatter
    }

    public func title(for item: VideoItem) -> String {
        guard let date = item.creationDate else { return "Video" }
        return dateFormatter.string(from: date)
    }

    public func subtitle(for item: VideoItem) -> String {
        item.albumTitle ?? "Photos"
    }

    public static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
