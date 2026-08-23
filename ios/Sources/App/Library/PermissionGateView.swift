import Photos
import SwiftUI
import UIKit

struct PermissionGateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var appeared = false

    var body: some View {
        ZStack {
            BackdropBackground()
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .symbolEffect(.breathe, options: .repeating)
                VStack(spacing: Theme.Spacing.s) {
                    Text("Backdrop")
                        .font(.largeTitle.bold())
                    Text("Your videos, playing behind everything else.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(explanation)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                button
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 360)
            .glassSurface()
            .padding(Theme.Spacing.l)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Theme.Motion.spring) { appeared = true }
            }
        }
    }

    private var explanation: String {
        switch model.access {
        case .denied:
            return "Photos access is off for Backdrop. Turn it on in Settings to see your videos here. Nothing leaves your phone."
        default:
            return "Backdrop reads your Photos library to list and play your videos — in Picture in Picture, in the background, with the Lock Screen player. Nothing is uploaded anywhere."
        }
    }

    @ViewBuilder
    private var button: some View {
        if model.access == .denied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button {
                Task { await model.requestAccess() }
            } label: {
                Label("Allow access to Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

/// Limited-access users pick which videos Backdrop may see. Needs a UIKit presenter.
enum LimitedLibraryPicker {
    @MainActor
    static func present() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
