import SwiftUI

/// A "modder-added" momentary button on the top-right of the chassis,
/// opposite the power slider. The chassis fires `GameBoyInput.menuPressed`
/// when pressed and clears it on release — what the press *does* is
/// owned by whatever's running in the screen slot (typically the
/// cartridge shelf's return-to-library confirmation).
internal struct MenuButton: View {

    let input: GameBoyInput
    let palette: GameBoyPalette
    let label: String

    @State private var isPressed: Bool = false
    @State private var hapticTrigger: Int = 0
    @Environment(\.deviceSettings) private var settings

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Expanded transparent hit target.
                Color.clear
                    .frame(width: 56, height: 28)
                    .contentShape(Rectangle())

                // Recessed pill button. Slightly different visual
                // language from start/select — wider, a hair taller,
                // with the label embossed on the button face itself
                // (rather than below it) so it reads as a single
                // "MENU" hardware affordance.
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.systemButtonHighlight,
                                    palette.systemButton
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 16)
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.30), lineWidth: 0.6)
                        )
                        .shadow(color: .black.opacity(isPressed ? 0.10 : 0.32),
                                radius: isPressed ? 0.5 : 2,
                                x: 0, y: isPressed ? 0.5 : 1.5)
                        .scaleEffect(isPressed ? 0.94 : 1.0)
                        .offset(y: isPressed ? 1 : 0)

                    Text(label)
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.systemButtonLabel)
                        .tracking(0.8)
                        .scaleEffect(isPressed ? 0.94 : 1.0)
                        .offset(y: isPressed ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            input.setButton(.menu, pressed: true)
                            if settings.hapticsEnabled { hapticTrigger &+= 1 }
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            input.setButton(.menu, pressed: false)
                        }
                    }
            )
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.85), trigger: hapticTrigger)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
        }
    }
}
