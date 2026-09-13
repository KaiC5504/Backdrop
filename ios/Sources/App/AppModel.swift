import Foundation
import Observation
import BackdropCore

/// Launch arguments CI uses to photograph screens it cannot otherwise reach.
/// UserDefaults picks `-key value` pairs up through NSArgumentDomain.
struct LaunchOptions {
    var initialScreen: String?
    var fixtureLibrary: Bool
    var forcedAccess: LibraryAccess?
    /// Stars three fixture videos so the Favourites screenshot is not the empty state.
    var fixtureFavourites: Bool

    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> LaunchOptions {
        let forced: LibraryAccess? = switch defaults.string(forKey: "fixtureAccess") {
        case "denied": .denied
        case "limited": .limited
        case "notDetermined": .notDetermined
        default: nil
        }
        return LaunchOptions(
            initialScreen: defaults.string(forKey: "initialScreen"),
            fixtureLibrary: defaults.bool(forKey: "fixtureLibrary"),
            forcedAccess: forced,
            fixtureFavourites: defaults.bool(forKey: "fixtureFavourites")
        )
    }
}

/// Composition root. Owns every long-lived object and the navigation flags.
@MainActor
@Observable
final class AppModel {
    static let favouritesTitle = "Favourites"

    let launch: LaunchOptions
    let log: DiagnosticsLog
    let store: PlaybackStore
    let library: any LibrarySource
    let audio: AudioSessionController
    let nowPlaying: NowPlayingController
    let engine: PlaybackEngine
    let playerHost: PlayerHost
    let formatter: VideoTitleFormatter

    var access: LibraryAccess
    var isPlayerPresented = false
    var isQueuePresented = false
    var isDiagnosticsPresented = false
    /// The library cell the player zooms out of. Empty when opened another way.
    var zoomSourceID: String = ""

    /// Starred ids in play order, mirrored from the store so views observe changes.
    private(set) var favouriteIDs: [String]
    /// The starred videos the library can currently see, in `favouriteIDs` order. One it
    /// cannot see (deleted, or outside a limited selection) stays starred but not listed.
    private(set) var favourites: [VideoItem] = []

    init(launch: LaunchOptions) {
        self.launch = launch
        let logURL = (try? DiagnosticsLog.defaultURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-diagnostics.log")
        let log = DiagnosticsLog(fileURL: logURL)
        self.log = log

        let storeURL = (try? PlaybackStore.defaultURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-state.json")
        let store = PlaybackStore(fileURL: storeURL)
        if let error = store.loadError {
            log.log("store.load.failed \(error)")
        }
        if launch.fixtureLibrary, launch.fixtureFavourites, store.favourites.isEmpty {
            for id in ["fixture-1", "fixture-3", "fixture-5"] { store.toggleFavourite(id) }
        }
        self.store = store
        favouriteIDs = store.favourites

        let formatter = VideoTitleFormatter()
        self.formatter = formatter

        let library: any LibrarySource = launch.fixtureLibrary
            ? FixtureLibrarySource(access: launch.forcedAccess ?? .full)
            : PhotosLibrary(log: log)
        self.library = library

        let audio = AudioSessionController(log: log)
        let nowPlaying = NowPlayingController(log: log)
        let engine = PlaybackEngine(
            library: library, store: store, audio: audio, nowPlaying: nowPlaying,
            log: log, formatter: formatter
        )
        let host = PlayerHost(player: engine.player, log: log)
        self.audio = audio
        self.nowPlaying = nowPlaying
        self.engine = engine
        self.playerHost = host
        access = launch.forcedAccess ?? library.access

        nowPlaying.registerCommands()
        host.onRestoreRequested = { [weak self] in
            self?.zoomSourceID = ""
            self?.isPlayerPresented = true
        }
        log.log("app.launch screen=\(launch.initialScreen ?? "-") fixture=\(launch.fixtureLibrary) access=\(access) favourites=\(favouriteIDs.count)")
        applyInitialScreen()
    }

    func requestAccess() async {
        access = await library.requestAccess()
    }

    /// The tapped video plays now and Favourites, in their order, are what follows. A tapped
    /// favourite starts the list from its own slot; anything else goes in front of the list.
    func play(_ item: VideoItem) {
        zoomSourceID = item.id
        engine.play(item, in: favourites)
        isPlayerPresented = true
    }

    func playNext(_ item: VideoItem) {
        engine.playNext(item)
    }

    func enqueue(_ item: VideoItem) {
        engine.enqueue(item)
    }

    func stopPlayback() {
        engine.stop()
        isQueuePresented = false
        isPlayerPresented = false
    }

    // MARK: Favourites

    func isFavourite(_ videoID: String) -> Bool {
        favouriteIDs.contains(videoID)
    }

    func toggleFavourite(_ item: VideoItem) {
        let starred = store.toggleFavourite(item.id)
        favouriteIDs = store.favourites
        if starred {
            favourites.append(Self.asFavourite(item))
        } else {
            favourites.removeAll { $0.id == item.id }
        }
        log.log("favourites.\(starred ? "add" : "remove") \(item.id) count=\(favouriteIDs.count)")
        noteStoreError()
    }

    /// Drops `videoID` into the slot `targetID` occupies; the target shifts to make room.
    /// Resolved by id, not grid index, because the grid may be missing unlisted favourites.
    func moveFavourite(_ videoID: String, onto targetID: String) {
        guard videoID != targetID, let index = store.favourites.firstIndex(of: targetID) else { return }
        store.moveFavourite(videoID, to: index)
        favouriteIDs = store.favourites
        favourites = Self.ordered(favourites, by: favouriteIDs)
        noteStoreError()
    }

    func refreshFavourites() async {
        let all = await library.allVideos()
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        favourites = store.favourites.compactMap { byID[$0] }.map(Self.asFavourite)
    }

    private static func asFavourite(_ item: VideoItem) -> VideoItem {
        var copy = item
        copy.albumTitle = favouritesTitle
        return copy
    }

    private static func ordered(_ items: [VideoItem], by ids: [String]) -> [VideoItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    private func noteStoreError() {
        if let error = store.lastWriteError { log.log("store.write.failed \(error)") }
    }

    private func applyInitialScreen() {
        switch launch.initialScreen {
        case "permission":
            access = launch.forcedAccess ?? .notDetermined
        case "player", "queue":
            let wantsQueue = launch.initialScreen == "queue"
            Task { [weak self] in
                guard let self else { return }
                let items = await library.allVideos()
                guard let first = items.first else { return }
                // Every fixture video rather than Favourites: the shot needs a full queue.
                zoomSourceID = first.id
                engine.play(first, in: items)
                isPlayerPresented = true
                if wantsQueue {
                    isQueuePresented = true
                }
            }
        case "diagnostics":
            isDiagnosticsPresented = true
        default:
            break
        }
    }
}
