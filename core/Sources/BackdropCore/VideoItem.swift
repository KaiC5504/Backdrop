import Foundation

public struct VideoItem: Hashable, Identifiable, Sendable, Codable {
    public enum Source: Hashable, Sendable, Codable {
        case photos(localIdentifier: String)
        /// Bundled or on-disk file. Only the fixture source produces this; the real
        /// library never does.
        case file(URL)
    }

    public let id: String
    public let source: Source
    public let duration: TimeInterval
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public var albumTitle: String?

    public init(
        id: String,
        source: Source,
        duration: TimeInterval,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        albumTitle: String? = nil
    ) {
        self.id = id
        self.source = source
        self.duration = duration
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.albumTitle = albumTitle
    }

    public var aspectRatio: Double {
        guard pixelWidth > 0, pixelHeight > 0 else { return 16.0 / 9.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

public struct AlbumItem: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case all
        /// Backdrop's own starred list, kept in the store. Not a Photos album.
        case favourites
        /// The Photos "Favorites" smart album.
        case photosFavorites
        case user
    }

    public static let allID = "all"
    public static let favouritesID = "favourites"

    public let id: String
    public let title: String
    public let kind: Kind
    public let count: Int

    public init(id: String, title: String, kind: Kind, count: Int) {
        self.id = id
        self.title = title
        self.kind = kind
        self.count = count
    }
}
