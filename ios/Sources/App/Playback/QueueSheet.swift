import SwiftUI
import BackdropCore

struct QueueSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        NavigationStack {
            List {
                if let current = engine.current {
                    Section("Now Playing") {
                        QueueRow(item: current, highlighted: true)
                    }
                }
                Section("Up Next") {
                    if engine.queue.upcoming.isEmpty {
                        Text("Nothing queued. Long-press a video in the library to add it.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(engine.queue.upcoming) { entry in
                        QueueRow(item: entry.item, highlighted: false)
                            .contentShape(Rectangle())
                            .onTapGesture { engine.jump(to: entry.id) }
                    }
                    .onMove { engine.moveUpcoming(fromOffsets: $0, toOffset: $1) }
                    .onDelete { engine.removeUpcoming(atOffsets: $0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.isQueuePresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
    }
}

struct QueueRow: View {
    @Environment(AppModel.self) private var model
    let item: VideoItem
    let highlighted: Bool
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Theme.Colors.surface
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.formatter.title(for: item))
                    .font(.subheadline.weight(highlighted ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(model.formatter.subtitle(for: item)) · \(VideoTitleFormatter.durationLabel(item.duration))")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if highlighted {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.Colors.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: model.engine.isPlaying)
            }
        }
        .listRowBackground(Color.white.opacity(highlighted ? 0.08 : 0.04))
        .task(id: item.id) {
            image = await model.library.thumbnail(for: item, size: CGSize(width: 112, height: 112))
        }
    }
}
