import AVFoundation
import UIKit
import BackdropCore

enum LibraryAccess: Equatable {
    case notDetermined, denied, limited, full

    var canRead: Bool { self == .full || self == .limited }
}

enum LibraryError: LocalizedError {
    case assetMissing
    case playerItemUnavailable(String?)
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .assetMissing: return "This video is no longer in Photos."
        case .playerItemUnavailable(let detail): return detail ?? "Couldn't load this video."
        case .unsupportedSource: return "Unsupported video source."
        }
    }
}

/// Everything the app needs from "where the videos live". Photos in production; a
/// bundled clip for CI and screenshots.
@MainActor
protocol LibrarySource: AnyObject {
    var access: LibraryAccess { get }
    func requestAccess() async -> LibraryAccess
    func allVideos() async -> [VideoItem]
    func albums() async -> [AlbumItem]
    func videos(in album: AlbumItem) async -> [VideoItem]
    func thumbnail(for item: VideoItem, size: CGSize) async -> UIImage?
    func playerItem(for item: VideoItem) async throws -> AVPlayerItem
    /// Yields whenever the underlying library changed and lists should be re-fetched.
    var changes: AsyncStream<Void> { get }
}
