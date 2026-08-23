import AVKit
import UIKit
import BackdropCore

/// Owns the app's single AVPlayerViewController for the whole process. PiP dies the
/// moment the controller is deallocated, and SwiftUI destroys a cover's content on
/// dismiss — so the SwiftUI player screen only borrows this controller.
@MainActor
final class PlayerHost: NSObject {
    let controller = AVPlayerViewController()
    private(set) var isPictureInPictureActive = false
    private var pictureInPictureStarting = false

    /// Experiment switch read on every background transition. Default on: the
    /// documented way to keep audio going when a video player is backgrounded without PiP.
    var detachOnBackground: Bool {
        get { UserDefaults.standard.object(forKey: "detachOnBackground") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "detachOnBackground") }
    }

    /// The PiP window's "go back to app" button. The app should show the player screen.
    var onRestoreRequested: (@MainActor () -> Void)?
    /// Fires on didEnterBackground before any detach; the engine saves progress here.
    var onBackground: (@MainActor () -> Void)?

    private let player: AVPlayer
    private let log: DiagnosticsLog
    private var observers: [NSObjectProtocol] = []

    init(player: AVPlayer, log: DiagnosticsLog) {
        self.player = player
        self.log = log
        super.init()
        controller.player = player
        controller.delegate = self
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        // Backdrop publishes Now Playing itself; two writers fight over the card.
        controller.updatesNowPlayingInfoCenter = false
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        // Our own speed control keeps the engine, the store and Now Playing in sync.
        controller.speeds = []
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnterBackground() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.willEnterForeground() }
        })
    }

    func attachPlayer() {
        if controller.player !== player {
            controller.player = player
        }
    }

    private func didEnterBackground() {
        onBackground?()
        let pip = isPictureInPictureActive || pictureInPictureStarting
        if detachOnBackground && !pip {
            controller.player = nil
            log.log("app.background detached=true")
        } else {
            log.log("app.background detached=false pip=\(pip)")
        }
    }

    private func willEnterForeground() {
        if controller.player == nil {
            controller.player = player
            log.log("app.foreground reattached")
        } else {
            log.log("app.foreground")
        }
    }
}

extension PlayerHost: AVPlayerViewControllerDelegate {
    nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated {
            pictureInPictureStarting = true
            log.log("pip.willStart")
        }
    }

    nonisolated func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated {
            isPictureInPictureActive = true
            pictureInPictureStarting = false
            log.log("pip.didStart")
        }
    }

    nonisolated func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: any Error) {
        MainActor.assumeIsolated {
            pictureInPictureStarting = false
            log.log("pip.failed \(error.localizedDescription)")
        }
    }

    nonisolated func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated { log.log("pip.willStop") }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated {
            isPictureInPictureActive = false
            log.log("pip.didStop")
        }
    }

    nonisolated func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        false
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            log.log("pip.restore")
            onRestoreRequested?()
        }
        completionHandler(true)
    }
}
