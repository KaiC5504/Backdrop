import AVFoundation
import Photos
import UIKit
import BackdropCore

@MainActor
final class PhotosLibrary: NSObject, LibrarySource {
    let changes: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation
    private let imageManager = PHCachingImageManager()
    private let log: DiagnosticsLog

    init(log: DiagnosticsLog) {
        self.log = log
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        changes = stream
        changeContinuation = continuation
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    var access: LibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> LibraryAccess {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let mapped = Self.map(status)
        log.log("photos.access \(mapped)")
        return mapped
    }

    private static func map(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private static var videosNewestFirst: PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    func allVideos() async -> [VideoItem] {
        let result = PHAsset.fetchAssets(with: .video, options: Self.videosNewestFirst)
        return Self.items(from: result, albumTitle: nil)
    }

    func albums() async -> [AlbumItem] {
        var out: [AlbumItem] = []
        let total = PHAsset.fetchAssets(with: .video, options: Self.videosNewestFirst).count
        out.append(AlbumItem(id: AlbumItem.allID, title: "All", kind: .all, count: total))

        let favourites = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
        favourites.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: Self.videosNewestFirst).count
            if count > 0 {
                out.append(AlbumItem(id: collection.localIdentifier, title: "Favorites", kind: .favorites, count: count))
            }
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: Self.videosNewestFirst).count
            if count > 0 {
                out.append(AlbumItem(id: collection.localIdentifier,
                                     title: collection.localizedTitle ?? "Album",
                                     kind: .user, count: count))
            }
        }
        return out
    }

    func videos(in album: AlbumItem) async -> [VideoItem] {
        if album.kind == .all { return await allVideos() }
        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [album.id], options: nil
        ).firstObject else { return [] }
        let result = PHAsset.fetchAssets(in: collection, options: Self.videosNewestFirst)
        return Self.items(from: result, albumTitle: album.title)
    }

    private static func items(from result: PHFetchResult<PHAsset>, albumTitle: String?) -> [VideoItem] {
        var items: [VideoItem] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(VideoItem(
                id: asset.localIdentifier,
                source: .photos(localIdentifier: asset.localIdentifier),
                duration: asset.duration,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                albumTitle: albumTitle
            ))
        }
        return items
    }

    private func asset(for item: VideoItem) -> PHAsset? {
        guard case .photos(let id) = item.source else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func thumbnail(for item: VideoItem, size: CGSize) async -> UIImage? {
        guard let asset = asset(for: item) else { return nil }
        let options = PHImageRequestOptions()
        // highQualityFormat means exactly one callback, which a continuation needs.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        // Points in, pixels out. 2x is plenty for a grid cell or a Lock Screen card.
        let target = CGSize(width: size.width * 2, height: size.height * 2)
        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    func playerItem(for item: VideoItem) async throws -> AVPlayerItem {
        switch item.source {
        case .file(let url):
            return AVPlayerItem(url: url)
        case .photos:
            guard let asset = asset(for: item) else { throw LibraryError.assetMissing }
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            return try await withCheckedThrowingContinuation { continuation in
                var resumed = false
                imageManager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                    guard !resumed else { return }
                    resumed = true
                    if let playerItem {
                        continuation.resume(returning: playerItem)
                    } else {
                        let detail = (info?[PHImageErrorKey] as? NSError)?.localizedDescription
                        continuation.resume(throwing: LibraryError.playerItemUnavailable(detail))
                    }
                }
            }
        }
    }
}

extension PhotosLibrary: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        changeContinuation.yield(())
    }
}
