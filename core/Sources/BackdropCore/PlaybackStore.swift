import Foundation

/// One small JSON file. Write-through: every mutation rewrites the file atomically.
/// The contents are a few hundred bytes, so there is nothing to debounce.
/// Not thread-safe by design — the engine owns it from the main actor.
public final class PlaybackStore {
    public struct Contents: Codable, Equatable, Sendable {
        public var positions: [String: TimeInterval] = [:]
        public var speed: Double = 1
        public var loop: Bool = false
        /// Video ids in the order the user arranged them.
        public var favourites: [String] = []
        public init() {}

        private enum CodingKeys: String, CodingKey {
            case positions, speed, loop, favourites
        }

        // A key added after a build shipped has to be optional on read, or the first
        // launch after an update would throw the whole file away.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            positions = try c.decodeIfPresent([String: TimeInterval].self, forKey: .positions) ?? [:]
            speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
            loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
            favourites = try c.decodeIfPresent([String].self, forKey: .favourites) ?? []
        }
    }

    public let fileURL: URL
    public private(set) var loadError: String?
    public private(set) var lastWriteError: String?

    private var contents: Contents {
        didSet { persist() }
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        var loaded = Contents()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                loaded = try JSONDecoder().decode(Contents.self, from: data)
            } catch {
                loadError = "\(error)"
            }
        }
        contents = loaded
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Backdrop", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    public var snapshot: Contents { contents }

    public func position(for videoID: String) -> TimeInterval? {
        contents.positions[videoID]
    }

    public func setPosition(_ seconds: TimeInterval?, for videoID: String) {
        guard contents.positions[videoID] != seconds else { return }
        contents.positions[videoID] = seconds
    }

    public var speed: Double {
        get { contents.speed }
        set { if contents.speed != newValue { contents.speed = newValue } }
    }

    public var loop: Bool {
        get { contents.loop }
        set { if contents.loop != newValue { contents.loop = newValue } }
    }

    public var favourites: [String] { contents.favourites }

    public func isFavourite(_ videoID: String) -> Bool {
        contents.favourites.contains(videoID)
    }

    /// Returns whether the video is a favourite after the toggle.
    @discardableResult
    public func toggleFavourite(_ videoID: String) -> Bool {
        if let i = contents.favourites.firstIndex(of: videoID) {
            contents.favourites.remove(at: i)
            return false
        }
        contents.favourites.append(videoID)
        return true
    }

    /// Takes the video out and puts it back at `index` of the remaining list, clamped.
    /// Dropping onto another video's slot is exactly this with that video's index.
    public func moveFavourite(_ videoID: String, to index: Int) {
        guard let from = contents.favourites.firstIndex(of: videoID) else { return }
        var list = contents.favourites
        list.remove(at: from)
        list.insert(videoID, at: min(max(index, 0), list.count))
        if list != contents.favourites { contents.favourites = list }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(contents)
            try data.write(to: fileURL, options: .atomic)
            lastWriteError = nil
        } catch {
            lastWriteError = "\(error)"
        }
    }
}
