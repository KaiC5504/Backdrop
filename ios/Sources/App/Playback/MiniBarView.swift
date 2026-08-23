import SwiftUI
import BackdropCore

struct MiniBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        HStack(spacing: Theme.Spacing.m) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.current.map { model.formatter.title(for: $0) } ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(engine.current.map { model.formatter.subtitle(for: $0) } ?? "")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: Theme.Sizes.iconButton, height: Theme.Sizes.iconButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Button {
                model.stopPlayback()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .overlay(alignment: .bottom) { progressHairline }
        .glassSurface(cornerRadius: Theme.Radius.banner)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture { model.isPlayerPresented = true }
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height > 48 { model.stopPlayback() }
            }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: engine.isPlaying)
    }

    private var thumbnail: some View {
        ZStack {
            Theme.Colors.surface
            if let image = model.engine.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: Theme.Sizes.miniBarThumb, height: Theme.Sizes.miniBarThumb)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
    }

    private var progressHairline: some View {
        GeometryReader { geo in
            let engine = model.engine
            let fraction = engine.duration > 0 ? min(max(engine.time / engine.duration, 0), 1) : 0
            Capsule()
                .fill(Theme.Colors.accent)
                .frame(width: max(geo.size.width * fraction, 0), height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
    }
}
