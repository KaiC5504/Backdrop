import AVKit
import SwiftUI
import BackdropCore

/// The system player inline, inside Backdrop's own chrome. Inline (not a modal AVKit
/// presentation) is what `canStartPictureInPictureAutomaticallyFromInline` is for, and it
/// keeps our controls clear of AVKit's overlay. Landscape goes edge to edge.
struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            ZStack {
                BackdropBackground()
                if verticalSizeClass == .compact {
                    landscape
                } else {
                    portrait(in: geo.size)
                }
            }
        }
        .sheet(isPresented: $model.isQueuePresented) { QueueSheet() }
        .onAppear { model.playerHost.attachPlayer() }
        .statusBarHidden(verticalSizeClass == .compact)
    }

    private var landscape: some View {
        ZStack(alignment: .topLeading) {
            PlayerHostView(host: model.playerHost)
                .ignoresSafeArea()
            GlassIconButton(systemName: "chevron.down") { model.isPlayerPresented = false }
                .padding(Theme.Spacing.m)
        }
    }

    private func portrait(in size: CGSize) -> some View {
        let ratio = model.engine.current?.aspectRatio ?? 16.0 / 9.0
        let videoHeight = min(size.width / ratio, size.height * 0.5)
        return VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
            PlayerHostView(host: model.playerHost)
                .frame(width: size.width, height: videoHeight)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cell, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            PlayerControls()
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.l)
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack {
            GlassIconButton(systemName: "chevron.down") { model.isPlayerPresented = false }
            Spacer()
            Text("Now Playing")
                .font(.caption.weight(.semibold))
                .kerning(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Color.clear.frame(width: Theme.Sizes.iconButton, height: Theme.Sizes.iconButton)
        }
        .padding(.top, Theme.Spacing.s)
    }
}

/// Borrows the app-lifetime AVPlayerViewController. Never creates or destroys it — PiP
/// would die with it.
struct PlayerHostView: UIViewControllerRepresentable {
    let host: PlayerHost

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = .black
        embed(in: container)
        return container
    }

    func updateUIViewController(_ container: UIViewController, context: Context) {
        if host.controller.parent !== container {
            embed(in: container)
        }
    }

    static func dismantleUIViewController(_ container: UIViewController, coordinator: ()) {
        for child in container.children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    private func embed(in container: UIViewController) {
        let player = host.controller
        if let oldParent = player.parent, oldParent !== container {
            player.willMove(toParent: nil)
            player.view.removeFromSuperview()
            player.removeFromParent()
        }
        container.addChild(player)
        player.view.frame = container.view.bounds
        player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(player.view)
        player.didMove(toParent: container)
    }
}
