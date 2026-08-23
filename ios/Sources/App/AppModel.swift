import Foundation
import Observation
import BackdropCore

/// Launch arguments CI uses to photograph screens it cannot otherwise reach.
/// UserDefaults picks `-key value` pairs up through NSArgumentDomain.
struct LaunchOptions {
    var initialScreen: String?
    var fixtureLibrary: Bool
    var forcedAccess: LibraryAccess?

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
            forcedAccess: forced
        )
    }
}

/// Composition root. Owns every long-lived object and the navigation flags.
@MainActor
@Observable
final class AppModel {
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
        self.store = store

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
        host.onBackground = { [weak engine] in engine?.saveProgressNow() }
        host.onRestoreRequested = { [weak self] in
            self?.zoomSourceID = ""
            self?.isPlayerPresented = true
        }
        log.log("app.launch screen=\(launch.initialScreen ?? "-") fixture=\(launch.fixtureLibrary) access=\(access)")
        applyInitialScreen()
    }

    func requestAccess() async {
        access = await library.requestAccess()
    }

    func play(_ item: VideoItem, in list: [VideoItem]) {
        zoomSourceID = item.id
        engine.play(item, in: list)
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
                play(first, in: items)
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
