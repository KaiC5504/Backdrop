import SwiftUI
import BackdropCore

struct VideoCell: View {
    @Environment(AppModel.self) private var model
    let item: VideoItem
    let index: Int
    let animateIn: Bool

    @State private var image: UIImage?
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        Theme.Colors.surface
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(VideoTitleFormatter.durationLabel(item.duration))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassCapsule()
                        .padding(Theme.Spacing.s)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cell, style: .continuous))
            Text(model.formatter.title(for: item))
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .scrollTransition(.interactive) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.65)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .onAppear {
            if animateIn {
                let delay = Double(min(index, 11)) * Theme.Motion.staggerStep
                withAnimation(Theme.Motion.spring.delay(delay)) { appeared = true }
            } else {
                appeared = true
            }
        }
        .task(id: item.id) {
            let loaded = await model.library.thumbnail(for: item, size: Theme.Sizes.thumbnailRequest)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}
