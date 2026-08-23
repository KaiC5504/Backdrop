import SwiftUI

struct PlayerScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            BackdropBackground()
            VStack(spacing: Theme.Spacing.l) {
                GlassIconButton(systemName: "chevron.down") { model.isPlayerPresented = false }
                Text("Player arrives in Task 12")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
