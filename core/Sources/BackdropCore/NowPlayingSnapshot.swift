import Foundation

/// Everything the Now Playing card needs, with no MediaPlayer types so it can be built
/// and tested here. The app maps it onto MPNowPlayingInfoCenter keys.
public struct NowPlayingSnapshot: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var playbackRate: Double
    public var defaultRate: Double
    public var queueCount: Int
    public var queueIndex: Int

    public init(title: String, subtitle: String, duration: TimeInterval, elapsed: TimeInterval,
                playbackRate: Double, defaultRate: Double, queueCount: Int, queueIndex: Int) {
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
        self.elapsed = elapsed
        self.playbackRate = playbackRate
        self.defaultRate = defaultRate
        self.queueCount = queueCount
        self.queueIndex = queueIndex
    }
}

public enum NowPlayingSnapshotBuilder {
    public static func make(
        item: VideoItem,
        queue: PlaybackQueue,
        elapsed: TimeInterval,
        duration: TimeInterval?,
        isPlaying: Bool,
        speed: Double,
        formatter: VideoTitleFormatter
    ) -> NowPlayingSnapshot {
        let resolvedDuration = max(duration ?? item.duration, 0)
        let upper = resolvedDuration > 0 ? resolvedDuration : max(elapsed, 0)
        let clampedElapsed = min(max(elapsed, 0), upper)
        return NowPlayingSnapshot(
            title: formatter.title(for: item),
            subtitle: formatter.subtitle(for: item),
            duration: resolvedDuration,
            elapsed: clampedElapsed,
            playbackRate: isPlaying ? speed : 0,
            defaultRate: speed,
            queueCount: queue.count,
            queueIndex: queue.currentIndex ?? 0
        )
    }
}
