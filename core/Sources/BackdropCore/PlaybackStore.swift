import Foundation

/// One small JSON file. Write-through: every mutation rewrites the file atomically.
/// The contents are a few hundred bytes, so there is nothing to debounce.
/// Not thread-safe by design — the engine owns it from the main actor.
public final class PlaybackStore {
    public struct Contents: Codable, Equatable, Sendable {
        public var positions: [String: TimeInterval] = [:]
        public var speed: Double = 1
        public var loop: Bool = false
        public init() {}
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
