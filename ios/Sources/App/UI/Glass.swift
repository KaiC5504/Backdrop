import SwiftUI

/// Read once — it is a launch argument, not something that changes mid-run.
private let legacyGlass = UserDefaults.standard.bool(forKey: "legacyGlass")

private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// iOS 26 Liquid Glass by default. CI launches with `-legacyGlass YES` because the
    /// simulator renders glassEffect inconsistently and screenshots are the only
    /// pre-device check; TestFlight builds get the real thing.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        if legacyGlass {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Colors.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        } else {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if legacyGlass {
            background(tint.map { AnyShapeStyle($0.opacity(0.35)) } ?? AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Colors.stroke, lineWidth: 1))
        } else {
            glassEffect(makeGlass(tint: tint, interactive: interactive), in: Capsule())
        }
    }

    func glassChip(selected: Bool) -> some View {
        glassCapsule(tint: selected ? Theme.Colors.accent : nil, interactive: true)
    }
}

/// A round glass button with an SF Symbol. Used for close, gear, play/pause everywhere.
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = Theme.Sizes.iconButton
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCapsule(tint: tint, interactive: true)
    }
}
