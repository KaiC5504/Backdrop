import SwiftUI
import BackdropCore

struct PlayerControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: 4) {
                Text(engine.current.map { model.formatter.title(for: $0) } ?? "—")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(engine.current.map { model.formatter.subtitle(for: $0) } ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if let message = engine.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.warning)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: Theme.Spacing.l) {
                GlassIconButton(systemName: "backward.fill", size: 52) { engine.previous() }
                Button {
                    engine.toggle()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassProminent)
                .clipShape(Circle())
                GlassIconButton(systemName: "forward.fill", size: 52) { engine.next() }
                    .opacity(engine.queue.hasNext ? 1 : 0.4)
                    .disabled(!engine.queue.hasNext)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: engine.isPlaying)
            .sensoryFeedback(.impact(weight: .light), trigger: engine.current?.id)

            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    chip(systemName: engine.loop ? "repeat.1" : "repeat", title: "Loop", active: engine.loop) {
                        engine.setLoop(!engine.loop)
                    }
                    SpeedMenu()
                    chip(systemName: "list.bullet", title: queueTitle, active: false) {
                        model.isQueuePresented = true
                    }
                }
            }
        }
    }

    private var queueTitle: String {
        let count = model.engine.queue.upcoming.count
        return count == 0 ? "Queue" : "Queue · \(count)"
    }

    private func chip(systemName: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.chipH)
                .padding(.vertical, Theme.Spacing.chipV)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassChip(selected: active)
    }
}

struct SpeedMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        Menu {
            ForEach(NowPlayingController.supportedRates, id: \.self) { rate in
                Button {
                    engine.setSpeed(rate)
                } label: {
                    if rate == engine.speed {
                        Label(Self.label(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.label(rate))
                    }
                }
            }
        } label: {
            Label(Self.label(engine.speed), systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.chipH)
                .padding(.vertical, Theme.Spacing.chipV)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassChip(selected: engine.speed != 1)
    }

    static func label(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
    }
}
