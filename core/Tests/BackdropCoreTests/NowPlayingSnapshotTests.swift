import Foundation
import Testing
@testable import BackdropCore

@Suite struct NowPlayingSnapshotTests {
    private let formatter = VideoTitleFormatter(locale: Locale(identifier: "en_US_POSIX"),
                                                timeZone: TimeZone(identifier: "UTC")!)
    private let a = VideoItem(id: "a", source: .photos(localIdentifier: "a"), duration: 120,
                              creationDate: nil, pixelWidth: 1, pixelHeight: 1, albumTitle: "Gym")
    private let b = VideoItem(id: "b", source: .photos(localIdentifier: "b"), duration: 30,
                              creationDate: nil, pixelWidth: 1, pixelHeight: 1)

    @Test func pausedHasZeroRateButKeepsDefaultRate() {
        let q = PlaybackQueue(items: [a, b], startingAt: 0)
        let s = NowPlayingSnapshotBuilder.make(item: a, queue: q, elapsed: 10, duration: nil,
                                               isPlaying: false, speed: 1.5, formatter: formatter)
        #expect(s.playbackRate == 0)
        #expect(s.defaultRate == 1.5)
        #expect(s.title == "Video")
        #expect(s.subtitle == "Gym")
    }

    @Test func playingReportsSpeedAsRate() {
        let q = PlaybackQueue(items: [a, b], startingAt: 1)
        let s = NowPlayingSnapshotBuilder.make(item: b, queue: q, elapsed: 5, duration: 31,
                                               isPlaying: true, speed: 2, formatter: formatter)
        #expect(s.playbackRate == 2)
        #expect(s.duration == 31)
        #expect(s.queueCount == 2)
        #expect(s.queueIndex == 1)
    }

    @Test func durationFallsBackToItemAndElapsedIsClamped() {
        let q = PlaybackQueue(items: [a], startingAt: 0)
        let s = NowPlayingSnapshotBuilder.make(item: a, queue: q, elapsed: 500, duration: nil,
                                               isPlaying: true, speed: 1, formatter: formatter)
        #expect(s.duration == 120)
        #expect(s.elapsed == 120)
        let negative = NowPlayingSnapshotBuilder.make(item: a, queue: q, elapsed: -3, duration: nil,
                                                      isPlaying: true, speed: 1, formatter: formatter)
        #expect(negative.elapsed == 0)
    }
}
