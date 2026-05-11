import SwiftUI

/// Start and Select — two angled pill buttons in the middle-lower
/// region of the shell. Labels are customizable so consumers can
/// re-label them to MENU / PAUSE / whatever fits their game.
internal struct SystemButtons: View {
    let palette: GameBoyPalette
    let input: GameBoyInput
    let startLabel: String
    let selectLabel: String

    /// Tilt of the pair, in degrees counter-clockwise.
    var tilt: Double = 25

    var body: some View {
        HStack(spacing: 22) {
            PillButton(
                label: selectLabel,
                palette: palette,
                onChange: { pressed in input.setButton(.select, pressed: pressed) }
            )
            PillButton(
                label: startLabel,
                palette: palette,
                onChange: { pressed in input.setButton(.start, pressed: pressed) }
            )
        }
        .rotationEffect(.degrees(-tilt))
    }
}

private struct PillButton: View {
    let label: String
    let palette: GameBoyPalette
    let onChange: (Bool) -> Void

    @State private var isPressed: Bool = false
    @State private var hapticTrigger: Int = 0
    @Environment(\.deviceSettings) private var settings

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Transparent hit target larger than the visual.
                Color.clear
                    .frame(width: 64, height: 28)
                    .contentShape(Rectangle())
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [palette.systemButtonHighlight, palette.systemButton],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 12)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.30), lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(isPressed ? 0.10 : 0.30),
                            radius: isPressed ? 0.5 : 2,
                            x: 0, y: isPressed ? 0.5 : 1.5)
                    .scaleEffect(isPressed ? 0.94 : 1.0)
                    .offset(y: isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onChange(true)
                            if settings.hapticsEnabled { hapticTrigger &+= 1 }
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            onChange(false)
                        }
                    }
            )
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: hapticTrigger)

            Text(label)
                .font(GameBoyTypography.systemButtonLabelFont)
                .foregroundStyle(palette.systemButtonLabel)
                .tracking(0.8)
        }
    }
}
