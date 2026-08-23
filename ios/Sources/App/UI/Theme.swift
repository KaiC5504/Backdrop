import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(hex: 0x07080C)
        static let surface = Color.white.opacity(0.08)
        static let stroke = Color.white.opacity(0.12)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.62)
        static let accent = Color(hex: 0x8FA8FF)
        static let accentSoft = Color(hex: 0x8FA8FF).opacity(0.35)
        static let warning = Color(hex: 0xF2B263)
        static let surfaceFaint = Color.white.opacity(0.04)
        /// Nine stops for the 3×3 mesh, row by row. Deep indigo/violet/teal that
        /// reads as depth behind glass, never as a poster.
        static let mesh: [Color] = [
            Color(hex: 0x0B0F1E), Color(hex: 0x141A3A), Color(hex: 0x0A1626),
            Color(hex: 0x1A1330), Color(hex: 0x22204A), Color(hex: 0x0F2336),
            Color(hex: 0x07080C), Color(hex: 0x120E22), Color(hex: 0x0A1A2A),
        ]
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
        static let chipH: CGFloat = 12
        static let chipV: CGFloat = 10
    }

    enum Radius {
        static let cell: CGFloat = 18
        static let card: CGFloat = 28
        static let banner: CGFloat = 22
        static let pill: CGFloat = 12
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.9)
        /// Per-cell delay for the library's first appearance; capped at 12 cells.
        static let staggerStep: Double = 0.04
    }

    enum Sizes {
        static let miniBarThumb: CGFloat = 44
        static let iconButton: CGFloat = 44
        static let queueThumb: CGFloat = 56
        static let thumbnailRequest = CGSize(width: 270, height: 270)
        static let artworkRequest = CGSize(width: 400, height: 400)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
