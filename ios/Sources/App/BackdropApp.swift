import SwiftUI
import BackdropCore

@main
struct BackdropApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                BackdropBackground()
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 48))
                    Text("Backdrop")
                        .font(.largeTitle.bold())
                    Text(VideoTitleFormatter.durationLabel(3723))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.xl)
                .glassSurface()
            }
            .preferredColorScheme(.dark)
            .tint(Theme.Colors.accent)
        }
    }
}
