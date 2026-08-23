import MediaPlayer
import UIKit
import BackdropCore

@MainActor
protocol NowPlayingCommandHandling: AnyObject {
    func remotePlay()
    func remotePause()
    func remoteToggle()
    func remoteNext()
    func remotePrevious()
    func remoteSeek(to seconds: TimeInterval)
    func remoteSetRate(_ rate: Double)
}

/// The only type that touches MPNowPlayingInfoCenter and MPRemoteCommandCenter.
/// Elapsed time is pushed on state changes, not every tick — the system interpolates
/// from the rate, and a per-tick write makes the Lock Screen scrubber stutter.
@MainActor
final class NowPlayingController {
    static let supportedRates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    weak var handler: NowPlayingCommandHandling?

    private let log: DiagnosticsLog
    private var artwork: MPMediaItemArtwork?
    private var lastSnapshot: NowPlayingSnapshot?
    private var lastHasNext = false
    private var registered = false

    init(log: DiagnosticsLog) {
        self.log = log
    }

    func registerCommands() {
        guard !registered else { return }
        registered = true
        let center = MPRemoteCommandCenter.shared()

        register(center.playCommand) { handler, _ in handler.remotePlay() }
        register(center.pauseCommand) { handler, _ in handler.remotePause() }
        register(center.togglePlayPauseCommand) { handler, _ in handler.remoteToggle() }
        register(center.nextTrackCommand) { handler, _ in handler.remoteNext() }
        register(center.previousTrackCommand) { handler, _ in handler.remotePrevious() }
        register(center.changePlaybackPositionCommand) { handler, event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                handler.remoteSeek(to: event.positionTime)
            }
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.supportedRates.map { NSNumber(value: $0) }
        register(center.changePlaybackRateCommand) { handler, event in
            if let event = event as? MPChangePlaybackRateCommandEvent {
                handler.remoteSetRate(Double(event.playbackRate))
            }
        }
        // Disabled so the card shows previous/next rather than ±15 s.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        log.log("nowplaying.commands.registered")
    }

    private func register(
        _ command: MPRemoteCommand,
        _ action: @escaping @MainActor (NowPlayingCommandHandling, MPRemoteCommandEvent) -> Void
    ) {
        command.isEnabled = true
        command.addTarget { [weak self] event in
            // Not documented to arrive on the main thread, so hop rather than assume.
            Task { @MainActor [weak self] in
                guard let handler = self?.handler else { return }
                action(handler, event)
            }
            return .success
        }
    }

    func publish(_ snapshot: NowPlayingSnapshot, hasNext: Bool) {
        lastSnapshot = snapshot
        lastHasNext = hasNext
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.subtitle,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.defaultRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: snapshot.queueCount,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: snapshot.queueIndex,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
        // Previous restarts at the head, so it is always meaningful.
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = true
    }

    func setArtwork(_ image: UIImage?) {
        artwork = image.map { image in
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        if let lastSnapshot {
            publish(lastSnapshot, hasNext: lastHasNext)
        }
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
        lastSnapshot = nil
        log.log("nowplaying.cleared")
    }
}
