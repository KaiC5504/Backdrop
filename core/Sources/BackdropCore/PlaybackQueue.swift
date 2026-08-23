import Foundation

public struct QueueEntry: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let item: VideoItem

    public init(item: VideoItem, id: UUID = UUID()) {
        self.id = id
        self.item = item
    }
}

/// Pure ordering model. Knows nothing about AVFoundation.
public struct PlaybackQueue: Equatable, Sendable {
    public enum PreviousAction: Equatable, Sendable {
        case restart
        case item(VideoItem)
        case none
    }

    /// Past this many seconds "previous" restarts the current video instead of
    /// going back — the convention every music player follows.
    public static let restartThreshold: TimeInterval = 3

    public private(set) var entries: [QueueEntry] = []
    public private(set) var currentIndex: Int?

    public init() {}

    public init(items: [VideoItem], startingAt index: Int) {
        replace(with: items, startingAt: index)
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }
    public var items: [VideoItem] { entries.map(\.item) }

    public var currentEntry: QueueEntry? {
        guard let i = currentIndex, entries.indices.contains(i) else { return nil }
        return entries[i]
    }

    public var current: VideoItem? { currentEntry?.item }

    public var upcoming: [QueueEntry] {
        guard let i = currentIndex, i + 1 <= entries.count else { return [] }
        return Array(entries[(i + 1)...])
    }

    public var hasNext: Bool {
        guard let i = currentIndex else { return false }
        return i + 1 < entries.count
    }

    public var hasPrevious: Bool {
        guard let i = currentIndex else { return false }
        return i > 0
    }

    public mutating func replace(with items: [VideoItem], startingAt index: Int) {
        entries = items.map { QueueEntry(item: $0) }
        currentIndex = entries.isEmpty ? nil : min(max(index, 0), entries.count - 1)
    }

    public mutating func playNext(_ item: VideoItem) {
        guard let i = currentIndex else {
            entries = [QueueEntry(item: item)]
            currentIndex = 0
            return
        }
        entries.insert(QueueEntry(item: item), at: i + 1)
    }

    public mutating func append(_ item: VideoItem) {
        entries.append(QueueEntry(item: item))
        if currentIndex == nil { currentIndex = 0 }
    }

    @discardableResult
    public mutating func advance() -> VideoItem? {
        guard hasNext, let i = currentIndex else { return nil }
        currentIndex = i + 1
        return current
    }

    public mutating func previous(elapsed: TimeInterval) -> PreviousAction {
        guard let i = currentIndex else { return .none }
        if elapsed > Self.restartThreshold || i == 0 { return .restart }
        currentIndex = i - 1
        return .item(entries[i - 1].item)
    }

    @discardableResult
    public mutating func jump(to entryID: UUID) -> VideoItem? {
        guard let i = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        currentIndex = i
        return entries[i].item
    }

    /// Offsets are in `upcoming` coordinates, with the same meaning as SwiftUI's
    /// `onMove` (destination is an index in the list before removal).
    public mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let i = currentIndex else { return }
        let base = i + 1
        guard base <= entries.count else { return }
        var tail = Array(entries[base...])
        tail.moveElements(fromOffsets: source, toOffset: destination)
        entries.replaceSubrange(base..., with: tail)
    }

    public mutating func removeUpcoming(atOffsets offsets: IndexSet) {
        guard let i = currentIndex else { return }
        let base = i + 1
        for offset in offsets.sorted(by: >) where base + offset < entries.count {
            entries.remove(at: base + offset)
        }
    }

    public mutating func clear() {
        entries = []
        currentIndex = nil
    }
}

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, which lives in SwiftUI
    /// and is out of reach for this package.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.compactMap { indices.contains($0) ? self[$0] : nil }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
        let insertAt = Swift.min(Swift.max(destination - removedBeforeDestination, 0), count)
        insert(contentsOf: moving, at: insertAt)
    }
}
