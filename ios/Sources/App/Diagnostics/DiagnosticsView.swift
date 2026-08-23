import SwiftUI

/// An instrument, not a feature: the phone can never be plugged into the build machine,
/// so the log and the experiment switch are how device behaviour gets reported back.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var detach = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Detach player on background", isOn: $detach)
                        .onChange(of: detach) { _, value in
                            model.playerHost.detachOnBackground = value
                            model.log.log("diag.detachOnBackground \(value)")
                        }
                } header: {
                    Text("Experiments")
                } footer: {
                    Text("On: when the app goes to the background without Picture in Picture, the video view lets go of the player so the audio keeps going. Off: tests whether iOS keeps playing without that. Lock the phone while playing (no PiP) and compare.")
                }
                Section("Log") {
                    ShareLink(item: model.log.fileURL) {
                        Label("Share log", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        model.log.clear()
                        text = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
                Section {
                    Text(text.isEmpty ? "Empty." : text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.isDiagnosticsPresented = false }
                }
            }
        }
        .onAppear {
            detach = model.playerHost.detachOnBackground
            refresh()
        }
    }

    /// The file is capped at 1 MB; a Text of that size is slow. Show the tail.
    private func refresh() {
        let lines = model.log.contents().split(separator: "\n", omittingEmptySubsequences: false)
        text = lines.suffix(300).joined(separator: "\n")
    }
}
