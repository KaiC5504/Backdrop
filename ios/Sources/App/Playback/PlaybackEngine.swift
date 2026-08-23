import AVFoundation
import Observation
import UIKit
import BackdropCore

/// Owns the one AVPlayer. Everything that changes what is playing goes through here, so
/// the store, Now Playing and the UI can never disagree about it.
@MainActor
@Observable
final class PlaybackEngine {
    let player = AVPlayer()

    private(set) var queue = PlaybackQueue()
    private(set) var current: VideoItem?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var speed: Double
    private(set) var loop: Bool
    private(set) var errorMessage: String?
    private(set) var artwork: UIImage?

    @ObservationIgnored private let library: any LibrarySource
    @ObservationIgnored private let store: PlaybackStore
    @ObservationIgnored private let audio: AudioSessionController
    @ObservationIgnored private let nowPlaying: NowPlayingController
    @ObservationIgnored private let log: DiagnosticsLog
    @ObservationIgnored private let formatter: VideoTitleFormatter

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<AVPlayerItem?, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var prefetched: (id: String, item: AVPlayerItem)?
    @ObservationIgnored private var prefetchedID: String?
    @ObservationIgnored private var attachedItemID: String?
    @ObservationIgnored private var lastSavedAt: TimeInterval = 0
    @ObservationIgnored private var lastExternalPause: Date = .distantPast
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var isSeeking = false

    private static let saveInterval: TimeInterval = 5
    private static let timescale: CMTimeScale = 600

    init(
        library: any LibrarySource,
        store: PlaybackStore,
        audio: AudioSessionController,
        nowPlaying: NowPlayingController,
        log: DiagnosticsLog,
        formatter: VideoTitleFormatter
    ) {
        self.library = library
        self.store = store
        self.audio = audio
        self.nowPlaying = nowPlaying
        self.log = log
        self.formatter = formatter
        speed = store.speed
        loop = store.loop

        player.defaultRate = Float(speed)
        nowPlaying.handler = self

        audio.onInterruptionBegan = { [weak self] in self?.interruptionBegan() }
        audio.onInterruptionEnded = { [weak self] resume in self?.interruptionEnded(shouldResume: resume) }
        audio.onRouteLost = { [weak self] in self?.pause() }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: Self.timescale), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.itemDidPlayToEnd(note.object as? AVPlayerItem) }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.itemDidFail(note) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            // KVO thread is unspecified; read the live status on the main actor rather
            // than trusting a value that may be stale by the time the hop lands.
            Task { @MainActor [weak self] in self?.syncWithPlayerStatus() }
        }
    }

    // MARK: Commands

    func play(_ item: VideoItem, in list: [VideoItem]) {
        let index = list.firstIndex(where: { $0.id == item.id }) ?? 0
        let items = list.isEmpty ? [item] : list
        saveProgress()
        queue = PlaybackQueue(items: items, startingAt: index)
        loadCurrent(autoplay: true)
    }

    func play() {
        guard current != nil else { return }
        audio.activate()
        player.play()
        isPlaying = true
        publishNowPlaying()
        log.log("engine.play")
    }

    func pause() {
        guard current != nil else { return }
        player.pause()
        isPlaying = false
        saveProgress()
        publishNowPlaying()
        log.log("engine.pause")
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: TimeInterval) {
        guard current != nil, player.currentItem != nil, let itemID = attachedItemID else { return }
        let upper = duration > 0 ? duration : seconds
        let clamped = max(0, min(seconds, upper))
        time = clamped
        let generation = loadGeneration
        isSeeking = true
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: Self.timescale),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isSeeking = false
                guard finished, generation == loadGeneration else { return }
                publishNowPlaying()
                saveProgress(itemID: itemID, at: clamped)
            }
        }
    }

    func next() {
        guard queue.hasNext else { return }
        saveProgress()
        queue.advance()
        loadCurrent(autoplay: true)
    }

    func previous() {
        switch queue.previous(elapsed: time) {
        case .restart:
            seek(to: 0)
        case .item:
            saveProgress()
            loadCurrent(autoplay: true)
        case .none:
            break
        }
    }

    func setSpeed(_ value: Double) {
        let value = min(max(value, 0.5), 2.0)
        speed = value
        store.speed = value
        player.defaultRate = Float(value)
        if isPlaying {
            player.rate = Float(value)
        }
        publishNowPlaying()
        log.log("engine.speed \(value)")
    }

    func setLoop(_ value: Bool) {
        loop = value
        store.loop = value
        log.log("engine.loop \(value)")
    }

    func stop() {
        saveProgress()
        loadGeneration += 1
        loadTask?.cancel()
        prefetchTask?.cancel()
        artworkTask?.cancel()
        prefetched = nil
        prefetchTask = nil
        prefetchedID = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        attachedItemID = nil
        isPlaying = false
        isSeeking = false
        isBuffering = false
        current = nil
        queue.clear()
        time = 0
        duration = 0
        artwork = nil
        errorMessage = nil
        nowPlaying.clear()
        audio.deactivate()
        log.log("engine.stop")
    }

    func playNext(_ item: VideoItem) {
        if queue.isEmpty {
            play(item, in: [item])
            return
        }
        queue.playNext(item)
        refreshPrefetch()
        publishNowPlaying()
    }

    func enqueue(_ item: VideoItem) {
        if queue.isEmpty {
            play(item, in: [item])
            return
        }
        queue.append(item)
        refreshPrefetch()
        publishNowPlaying()
    }

    func jump(to entryID: UUID) {
        guard queue.jump(to: entryID) != nil else { return }
        saveProgress()
        loadCurrent(autoplay: true)
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpcoming(fromOffsets: source, toOffset: destination)
        refreshPrefetch()
    }

    func removeUpcoming(atOffsets offsets: IndexSet) {
        queue.removeUpcoming(atOffsets: offsets)
        refreshPrefetch()
        publishNowPlaying()
    }

    func saveProgressNow() {
        saveProgress()
    }

    // MARK: Loading

    private func loadCurrent(autoplay: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        guard let item = queue.current else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            attachedItemID = nil
            current = nil
            isPlaying = false
            isSeeking = false
            time = 0
            duration = 0
            nowPlaying.clear()
            return
        }
        current = item
        time = 0
        lastSavedAt = 0
        duration = item.duration
        isBuffering = true
        errorMessage = nil
        artwork = nil
        nowPlaying.setArtwork(nil)
        log.log("engine.load \(item.id) gen=\(generation)")
        publishNowPlaying()
        loadArtwork(for: item)

        if let ready = prefetched, ready.id == item.id {
            prefetched = nil
            prefetchedID = nil
            attach(ready.item, for: item, generation: generation, autoplay: autoplay)
            return
        }
        if prefetchedID == item.id, let task = prefetchTask {
            player.pause()
            player.replaceCurrentItem(with: nil)
            attachedItemID = nil
            loadTask = Task { [weak self] in
                guard let self else { return }
                let started = Date()
                let ready = await task.value
                let waited = Date().timeIntervalSince(started)
                if waited > 0.25 {
                    log.log("engine.gap \(String(format: "%.2f", waited))s waiting for prefetch \(item.id)")
                }
                guard generation == loadGeneration else { return }
                if prefetchedID == item.id {
                    prefetched = nil
                    prefetchedID = nil
                }
                if let ready {
                    loadTask = nil
                    attach(ready, for: item, generation: generation, autoplay: autoplay)
                } else {
                    await fetchAndAttach(item, generation: generation, autoplay: autoplay)
                }
            }
            return
        }
        prefetched = nil
        prefetchedID = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        attachedItemID = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            await fetchAndAttach(item, generation: generation, autoplay: autoplay)
        }
    }

    private func fetchAndAttach(_ item: VideoItem, generation: Int, autoplay: Bool) async {
        do {
            let playerItem = try await library.playerItem(for: item)
            guard generation == loadGeneration else { return }
            loadTask = nil
            attach(playerItem, for: item, generation: generation, autoplay: autoplay)
        } catch {
            guard generation == loadGeneration else { return }
            loadTask = nil
            isBuffering = false
            let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't load this video"
            log.log("engine.load.failed \(item.id) \(error)")
            if queue.hasNext {
                queue.advance()
                loadCurrent(autoplay: autoplay)
                errorMessage = "Skipped a video: \(message)"   // F5: set AFTER loadCurrent, which clears it
            } else {
                errorMessage = message
            }
        }
    }

    private func attach(_ playerItem: AVPlayerItem, for item: VideoItem, generation: Int, autoplay: Bool) {
        isSeeking = false
        playerItem.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: playerItem)
        attachedItemID = item.id
        let start = ResumePolicy.startTime(savedPosition: store.position(for: item.id), duration: item.duration)
        if start > 0 {
            time = start
            player.seek(to: CMTime(seconds: start, preferredTimescale: Self.timescale),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
        isBuffering = false
        if autoplay {
            play()
        } else {
            publishNowPlaying()
        }
        log.log("engine.attached \(item.id) start=\(Int(start))")

        Task { [weak self] in
            guard let self else { return }
            if let loaded = try? await playerItem.asset.load(.duration), loaded.isNumeric,
               loadGeneration == generation {
                duration = loaded.seconds
                publishNowPlaying()
            }
        }
        refreshPrefetch()
    }

    /// The next item's AVPlayerItem is fetched while the current one plays so the swap at
    /// the end is silent-gap-free — a silent app in the background is one iOS may suspend.
    private func refreshPrefetch() {
        guard let index = queue.currentIndex, index + 1 < queue.count else {
            prefetchTask?.cancel()
            prefetched = nil
            prefetchedID = nil
            return
        }
        let next = queue.entries[index + 1].item
        if prefetched?.id == next.id { return }
        if prefetchedID == next.id, prefetchTask != nil { return }
        prefetchTask?.cancel()
        prefetched = nil
        prefetchedID = next.id
        prefetchTask = Task { [weak self] in
            guard let self else { return nil }
            do {
                let item = try await library.playerItem(for: next)
                guard !Task.isCancelled else { return nil }
                item.audioTimePitchAlgorithm = .timeDomain
                prefetched = (next.id, item)
                log.log("engine.prefetched \(next.id)")
                return item
            } catch {
                log.log("engine.prefetch.failed \(next.id) \(error)")
                return nil
            }
        }
    }

    private func loadArtwork(for item: VideoItem) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let image = await library.thumbnail(for: item, size: Theme.Sizes.artworkRequest)
            guard !Task.isCancelled, current?.id == item.id else { return }
            artwork = image
            nowPlaying.setArtwork(image)
        }
    }

    // MARK: Events

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite, !isSeeking else { return }
        time = seconds
        if isPlaying, seconds - lastSavedAt >= Self.saveInterval || seconds < lastSavedAt {
            saveProgress()
        }
    }

    private func saveProgress(itemID: String? = nil, at seconds: TimeInterval? = nil) {
        guard let id = itemID ?? attachedItemID else { return }
        let position = seconds ?? time
        lastSavedAt = position
        store.setPosition(ResumePolicy.positionToStore(position: position, duration: duration), for: id)
    }

    private func itemDidPlayToEnd(_ ended: AVPlayerItem?) {
        guard let ended, ended === player.currentItem, let item = current else { return }
        log.log("engine.ended \(item.id)")
        store.setPosition(nil, for: item.id)
        if loop {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            time = 0
            isPlaying = true
            publishNowPlaying()
            return
        }
        if queue.hasNext {
            queue.advance()
            loadCurrent(autoplay: true)
        } else {
            isPlaying = false
            time = duration
            publishNowPlaying()
            log.log("engine.queue.finished")
        }
    }

    private func itemDidFail(_ note: Notification) {
        guard let failed = note.object as? AVPlayerItem, failed === player.currentItem, current != nil else { return }
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
        log.log("engine.item.failed \(error?.localizedDescription ?? "unknown")")
        if queue.hasNext {
            queue.advance()
            loadCurrent(autoplay: true)
            errorMessage = "Skipped a video: playback failed"
        } else {
            isPlaying = false
            errorMessage = "Playback failed"
            publishNowPlaying()
        }
    }

    /// The system player's own transport buttons drive the AVPlayer directly; this is
    /// how the engine (and therefore Now Playing and the store) finds out.
    private func syncWithPlayerStatus() {
        switch player.timeControlStatus {
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = true
            if !isPlaying, player.currentItem != nil {
                isPlaying = true
                audio.activate()
                publishNowPlaying()
                log.log("engine.play external (waiting)")
            }
        case .playing:
            isBuffering = false
            if !isPlaying {
                isPlaying = true
                audio.activate()
                publishNowPlaying()
                log.log("engine.play external")
            }
        case .paused:
            isBuffering = false
            if isPlaying, player.currentItem != nil {
                isPlaying = false
                lastExternalPause = Date()
                saveProgress()
                publishNowPlaying()
                log.log("engine.pause external")
            }
        @unknown default:
            break
        }
    }

    private func interruptionBegan() {
        resumeAfterInterruption = isPlaying || Date().timeIntervalSince(lastExternalPause) < 1.0
        if isPlaying {
            player.pause()
            isPlaying = false
            saveProgress()
            publishNowPlaying()
        }
    }

    private func interruptionEnded(shouldResume: Bool) {
        if shouldResume && resumeAfterInterruption {
            play()
        }
        resumeAfterInterruption = false
    }

    private func publishNowPlaying() {
        guard let item = current else {
            nowPlaying.clear()
            return
        }
        let snapshot = NowPlayingSnapshotBuilder.make(
            item: item,
            queue: queue,
            elapsed: time,
            duration: duration > 0 ? duration : nil,
            isPlaying: isPlaying,
            speed: speed,
            formatter: formatter
        )
        nowPlaying.publish(snapshot, hasNext: queue.hasNext)
    }
}

extension PlaybackEngine: NowPlayingCommandHandling {
    func remotePlay() { play() }
    func remotePause() { pause() }
    func remoteToggle() { toggle() }
    func remoteNext() { next() }
    func remotePrevious() { previous() }
    func remoteSeek(to seconds: TimeInterval) { seek(to: seconds) }
    func remoteSetRate(_ rate: Double) { setSpeed(rate) }
}
