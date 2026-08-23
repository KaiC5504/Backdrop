import SwiftUI

/// The ground every screen sits on: a slow-breathing mesh, still under reduced motion.
struct BackdropBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                mesh(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    mesh(phase: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func mesh(phase: Double) -> some View {
        let s = Float(sin(phase * 0.25))
        let c = Float(cos(phase * 0.18))
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + 0.14 * s, 0.5 + 0.12 * c], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: Theme.Colors.mesh
        )
        .background(Theme.Colors.background)
    }
}
