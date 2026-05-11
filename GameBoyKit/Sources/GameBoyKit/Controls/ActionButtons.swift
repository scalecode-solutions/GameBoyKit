import SwiftUI

/// The A and B circular action buttons. The pair is rotated as a whole
/// so A sits upper-right and B sits lower-left — the signature DMG
/// diagonal layout. Each button updates `GameBoyInput` independently.
internal struct ActionButtons: View {
    let palette: GameBoyPalette
    let input: GameBoyInput
    let aLabel: String
    let bLabel: String

    /// Tilt of the A/B pair, in degrees counter-clockwise.
    var tilt: Double = 25

    var body: some View {
        HStack(spacing: 18) {
            CircleButton(
                label: bLabel,
                palette: palette,
                onChange: { pressed in input.setButton(.b, pressed: pressed) }
            )
            CircleButton(
                label: aLabel,
                palette: palette,
                onChange: { pressed in input.setButton(.a, pressed: pressed) }
            )
        }
        .rotationEffect(.degrees(-tilt))
    }
}

private struct CircleButton: View {
    let label: String
    let palette: GameBoyPalette
    let onChange: (Bool) -> Void

    @State private var isPressed: Bool = false
    @State private var hapticTrigger: Int = 0
    @Environment(\.deviceSettings) private var settings

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer well (recessed look)
                Circle()
                    .fill(palette.actionButtonShadow.opacity(0.35))
                    .frame(width: 64, height: 64)
                    .blur(radius: 2)
                // Button cap
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [palette.actionButtonHighlight, palette.actionButton],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(palette.actionButtonShadow.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isPressed ? 0.10 : 0.35),
                            radius: isPressed ? 1 : 4,
                            x: 0, y: isPressed ? 1 : 3)
                    .scaleEffect(isPressed ? 0.92 : 1.0)
                    .offset(y: isPressed ? 2 : 0)
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
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
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: hapticTrigger)

            // Label under the button (rotated back to upright)
            Text(label)
                .font(GameBoyTypography.buttonLabelFont)
                .foregroundStyle(palette.actionButtonLabel)
                .tracking(1)
        }
    }
}
