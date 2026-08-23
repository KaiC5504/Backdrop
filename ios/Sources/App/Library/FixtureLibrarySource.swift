import AVFoundation
import UIKit
import BackdropCore

/// Six pretend videos backed by the one bundled clip. Exists so CI can photograph the
/// library, player and queue on a simulator with an empty Photos library.
@MainActor
final class FixtureLibrarySource: LibrarySource {
    let changes = AsyncStream<Void> { _ in }
    private(set) var access: LibraryAccess
    private let items: [VideoItem]
    private let albumList: [AlbumItem]

    static func bundledSampleURL() -> URL? {
        Bundle.main.url(forResource: "sample", withExtension: "mp4")
    }

    init(access: LibraryAccess) {
        self.access = access
        let url = Self.bundledSampleURL() ?? URL(fileURLWithPath: "/dev/null")
        let base = Date(timeIntervalSince1970: 1_787_493_900) // 2026-08-23 14:05 UTC
        let specs: [(Int, TimeInterval, Int, Int, String?)] = [
            (0, 8, 1920, 1080, nil),
            (1, 754, 1080, 1920, "Gym"),
            (2, 95, 1920, 1080, nil),
            (3, 3723, 3840, 2160, "Lectures"),
            (4, 42, 1080, 1920, "Gym"),
            (5, 600, 1920, 1080, "Lectures"),
        ]
        items = specs.map { index, duration, w, h, album in
            VideoItem(
                id: "fixture-\(index)",
                source: .file(url),
                duration: duration,
                creationDate: base.addingTimeInterval(-Double(index) * 86_400 * 3),
                pixelWidth: w,
                pixelHeight: h,
                albumTitle: album
            )
        }
        albumList = [
            AlbumItem(id: AlbumItem.allID, title: "All", kind: .all, count: items.count),
            AlbumItem(id: "fixture-gym", title: "Gym", kind: .user, count: 2),
            AlbumItem(id: "fixture-lectures", title: "Lectures", kind: .user, count: 2),
        ]
    }

    func requestAccess() async -> LibraryAccess {
        access = .full
        return access
    }

    func allVideos() async -> [VideoItem] { items }

    func albums() async -> [AlbumItem] { albumList }

    func videos(in album: AlbumItem) async -> [VideoItem] {
        if album.kind == .all { return items }
        return items.filter { $0.albumTitle == album.title }
    }

    func thumbnail(for item: VideoItem, size: CGSize) async -> UIImage? {
        // A deterministic gradient per item; real frames would all be the same clip.
        let index = Int(item.id.split(separator: "-").last ?? "0") ?? 0
        let hue = CGFloat((index * 47) % 360) / 360
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors = [
                UIColor(hue: hue, saturation: 0.55, brightness: 0.35, alpha: 1).cgColor,
                UIColor(hue: hue + 0.08, saturation: 0.6, brightness: 0.12, alpha: 1).cgColor,
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }

    func playerItem(for item: VideoItem) async throws -> AVPlayerItem {
        guard case .file(let url) = item.source else { throw LibraryError.unsupportedSource }
        return AVPlayerItem(url: url)
    }
}
