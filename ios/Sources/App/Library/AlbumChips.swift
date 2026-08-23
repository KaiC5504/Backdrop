import SwiftUI
import BackdropCore

struct AlbumChips: View {
    let albums: [AlbumItem]
    @Binding var selectedID: String

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(albums) { album in
                        let selected = album.id == selectedID
                        Button {
                            withAnimation(Theme.Motion.snappy) { selectedID = album.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(album.title)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                Text("\(album.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.chipH)
                            .padding(.vertical, Theme.Spacing.s)
                        }
                        .buttonStyle(.plain)
                        .glassChip(selected: selected)
                    }
                }
                // The grid pads its edges; the chip row bleeds past them and pads itself.
                .padding(.horizontal, Theme.Spacing.m)
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }
}
