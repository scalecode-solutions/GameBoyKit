import SwiftUI

/// Diagonal speaker grille, the strip of parallel slits in the
/// bottom-right of the shell. Renders six slits at ~-30° from vertical.
internal struct SpeakerGrille: View {
    let palette: GameBoyPalette
    var slitCount: Int = 6
    var slitWidth: CGFloat = 4
    var slitSpacing: CGFloat = 10
    var angleDegrees: Double = -30

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(0..<slitCount, id: \.self) { i in
                    Capsule()
                        .fill(palette.speakerGrilleColor.opacity(0.85))
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.18), lineWidth: 0.6)
                        )
                        .frame(width: slitWidth, height: size.height * 0.78)
                        .offset(x: offsetForIndex(i, size: size))
                        .rotationEffect(.degrees(angleDegrees))
                        .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 0.5)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func offsetForIndex(_ i: Int, size: CGSize) -> CGFloat {
        let total = CGFloat(slitCount - 1) * slitSpacing
        return CGFloat(i) * slitSpacing - total / 2
    }
}
