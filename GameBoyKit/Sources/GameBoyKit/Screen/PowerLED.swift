import SwiftUI

/// The red power LED in the lower-left of the screen bezel.
internal struct PowerLED: View {
    let palette: GameBoyPalette
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.ledRing)
                .frame(width: 14, height: 14)
            Circle()
                .fill(isOn ? palette.ledOn : palette.ledOff)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(isOn ? 0.55 : 0.10), .clear],
                                center: .init(x: 0.3, y: 0.3),
                                startRadius: 0,
                                endRadius: 5
                            )
                        )
                )
                .shadow(
                    color: isOn ? palette.ledOn.opacity(0.7) : .clear,
                    radius: 4
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}
