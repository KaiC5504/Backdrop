import Foundation
import Testing
@testable import BackdropCore

@Suite struct PlaybackQueueTests {
    private func v(_ id: String) -> VideoItem {
        VideoItem(id: id, source: .photos(localIdentifier: id), duration: 60,
                  creationDate: nil, pixelWidth: 1, pixelHeight: 1)
    }
    private let a = VideoItem(id: "a", source: .photos(localIdentifier: "a"), duration: 60, creationDate: nil, pixelWidth: 1, pixelHeight: 1)
    private let b = VideoItem(id: "b", source: .photos(localIdentifier: "b"), duration: 60, creationDate: nil, pixelWidth: 1, pixelHeight: 1)
    private let c = VideoItem(id: "c", source: .photos(localIdentifier: "c"), duration: 60, creationDate: nil, pixelWidth: 1, pixelHeight: 1)
    private let d = VideoItem(id: "d", source: .photos(localIdentifier: "d"), duration: 60, creationDate: nil, pixelWidth: 1, pixelHeight: 1)

    @Test func emptyQueue() {
        let q = PlaybackQueue()
        #expect(q.isEmpty)
        #expect(q.current == nil)
        #expect(!q.hasNext)
        #expect(!q.hasPrevious)
        #expect(q.upcoming.isEmpty)
    }

    @Test func startsAtRequestedIndexAndClamps() {
        let q = PlaybackQueue(items: [a, b, c], startingAt: 1)
        #expect(q.current == b)
        #expect(q.upcoming.map(\.item) == [c])
        let clamped = PlaybackQueue(items: [a, b], startingAt: 9)
        #expect(clamped.current == b)
        let negative = PlaybackQueue(items: [a, b], startingAt: -1)
        #expect(negative.current == a)
    }

    @Test func advanceWalksToEndThenStops() {
        var q = PlaybackQueue(items: [a, b], startingAt: 0)
        #expect(q.hasNext)
        #expect(q.advance() == b)
        #expect(!q.hasNext)
        #expect(q.advance() == nil)
        #expect(q.current == b)
    }

    @Test func previousRestartsWhenPastThreshold() {
        var q = PlaybackQueue(items: [a, b], startingAt: 1)
        #expect(q.previous(elapsed: 3.5) == .restart)
        #expect(q.current == b)
    }

    @Test func previousGoesBackEarlyInTheVideo() {
        var q = PlaybackQueue(items: [a, b], startingAt: 1)
        #expect(q.previous(elapsed: 1) == .item(a))
        #expect(q.current == a)
    }

    @Test func previousAtHeadRestarts() {
        var q = PlaybackQueue(items: [a, b], startingAt: 0)
        #expect(q.previous(elapsed: 0.5) == .restart)
        #expect(q.current == a)
    }

    @Test func previousOnEmptyIsNone() {
        var q = PlaybackQueue()
        #expect(q.previous(elapsed: 10) == PlaybackQueue.PreviousAction.none)
    }

    @Test func playNextInsertsAfterCurrent() {
        var q = PlaybackQueue(items: [a, b], startingAt: 0)
        q.playNext(c)
        #expect(q.items == [a, c, b])
        #expect(q.current == a)
    }

    @Test func playNextOnEmptyBecomesCurrent() {
        var q = PlaybackQueue()
        q.playNext(a)
        #expect(q.current == a)
        #expect(q.count == 1)
    }

    @Test func appendGoesToEnd() {
        var q = PlaybackQueue(items: [a], startingAt: 0)
        q.append(b)
        q.append(c)
        #expect(q.upcoming.map(\.item) == [b, c])
    }

    @Test func jumpByEntryID() {
        var q = PlaybackQueue(items: [a, b, c], startingAt: 0)
        let target = q.upcoming[1]
        #expect(q.jump(to: target.id) == c)
        #expect(q.current == c)
        #expect(q.jump(to: UUID()) == nil)
    }

    @Test func moveUpcomingUsesSwiftUIOffsetSemantics() {
        var q = PlaybackQueue(items: [a, b, c, d], startingAt: 0)
        // upcoming = [b, c, d]; move first to the end
        q.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(q.upcoming.map(\.item) == [c, d, b])
        // move last to the front
        q.moveUpcoming(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(q.upcoming.map(\.item) == [b, c, d])
        // moving onto itself is a no-op
        q.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        #expect(q.upcoming.map(\.item) == [b, c, d])
        #expect(q.current == a)
    }

    @Test func removeUpcoming() {
        var q = PlaybackQueue(items: [a, b, c, d], startingAt: 1)
        q.removeUpcoming(atOffsets: IndexSet([0, 1]))
        #expect(q.items == [a, b])
        #expect(q.current == b)
        #expect(!q.hasNext)
    }

    @Test func clearEmpties() {
        var q = PlaybackQueue(items: [a, b], startingAt: 1)
        q.clear()
        #expect(q.isEmpty)
        #expect(q.currentIndex == nil)
    }

    @Test func duplicatesGetDistinctEntryIDs() {
        let q = PlaybackQueue(items: [a, a], startingAt: 0)
        #expect(q.entries[0].id != q.entries[1].id)
    }
}
