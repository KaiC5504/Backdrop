import AVFoundation
import BackdropCore

/// The one place that talks to AVAudioSession. Stays active while paused so the Lock
/// Screen card survives a pause; deactivated only on an explicit stop.
@MainActor
final class AudioSessionController {
    var onInterruptionBegan: (@MainActor () -> Void)?
    var onInterruptionEnded: (@MainActor (_ shouldResume: Bool) -> Void)?
    var onRouteLost: (@MainActor () -> Void)?

    private(set) var isActive = false
    private let log: DiagnosticsLog
    private var observers: [NSObjectProtocol] = []

    init(log: DiagnosticsLog) {
        self.log = log
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        })
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        } catch {
            log.log("audio.session.category.failed \(error)")
        }
    }

    func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            if !isActive { log.log("audio.session.active") }
            isActive = true
        } catch {
            log.log("audio.session.activate.failed \(error)")
        }
    }

    func deactivate() {
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            log.log("audio.session.inactive")
        } catch {
            log.log("audio.session.deactivate.failed \(error)")
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            log.log("audio.interruption.began")
            onInterruptionBegan?()
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            log.log("audio.interruption.ended resume=\(shouldResume)")
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        log.log("audio.route.change reason=\(reason.rawValue)")
        if reason == .oldDeviceUnavailable {
            onRouteLost?()
        }
    }
}
