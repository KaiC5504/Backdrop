import SwiftUI
import BackdropCore

@main
struct BackdropApp: App {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel(launch: .fromUserDefaults()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoomNamespace

    var body: some View {
        @Bindable var model = model
        Group {
            if model.access.canRead {
                LibraryView(zoomNamespace: zoomNamespace)
            } else {
                PermissionGateView()
            }
        }
        .animation(Theme.Motion.spring, value: model.access)
        .fullScreenCover(isPresented: $model.isPlayerPresented) {
            PlayerScreen()
                .navigationTransition(.zoom(sourceID: model.zoomSourceID, in: zoomNamespace))
        }
    }
}
