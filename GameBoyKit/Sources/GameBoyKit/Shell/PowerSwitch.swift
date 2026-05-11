import SwiftUI

/// A DMG-style sliding power switch printed onto the chassis. The
/// real Game Boy had a small physical slider on the top of the device;
/// this is its 2D translation: a recessed track, a slider knob that
/// animates between OFF (left) and ON (right), and tiny "OFF / ON"
/// labels printed on the chassis around the track.
///
/// Treat it as part of the chassis chrome — it owns its own tap target
/// (bigger than the visual) and writes to the `isOn` binding.
internal struct PowerSwitch: View {

    @Binding var isOn: Bool
    let palette: GameBoyPalette

    @State private var hapticTrigger: Int = 0

    private let trackWidth: CGFloat = 54
    private let trackHeight: CGFloat = 17
    private let knobWidth: CGFloat = 24
    private let knobHeight: CGFloat = 14

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                // Left chassis label
                Text("◁OFF")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.subtitleColor)
                    .tracking(0.3)

                // The track + knob
                ZStack {
                    // Recessed channel
                    Capsule()
                        .fill(palette.shellEdgeShadow.opacity(0.55))
                        .frame(width: trackWidth, height: trackHeight)
                        .overlay(
                            // Inner shadow: top darker, bottom lighter
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.35),
                                            palette.shellEdgeHighlight.opacity(0.6)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.8
                                )
                        )

                    // Knob
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
                        .frame(width: knobWidth, height: knobHeight)
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.28), lineWidth: 0.4)
                        )
                        // Three grip ridges on the knob
                        .overlay(
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Capsule()
                                        .fill(palette.systemButtonShadow)
                                        .frame(width: 0.8, height: 6)
                                }
                            }
                            .opacity(0.6)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 0.6, x: 0, y: 0.5)
                        .offset(x: knobOffset)
                }

                // Right chassis label
                Text("ON▷")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.subtitleColor)
                    .tracking(0.3)
            }

            // POWER caption under the slider
            Text("POWER")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(palette.subtitleColor.opacity(0.75))
                .tracking(1.2)
        }
        // Expand the hit area generously beyond the visual.
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.toggle()
            hapticTrigger &+= 1
        }
        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: isOn)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.85), trigger: hapticTrigger)
        .accessibilityElement()
        .accessibilityLabel("Power")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    /// Knob x-offset from the track's center for OFF/ON positions.
    private var knobOffset: CGFloat {
        let travel = (trackWidth - knobWidth) / 2 - 1
        return isOn ? travel : -travel
    }

    /// Look for `systemButtonShadow` even though the palette doesn't
    /// expose it; reuse `actionButtonShadow` as the grip ridge tint.
}

// Tiny helper so the file compiles regardless of whether the palette
// exposes a dedicated `systemButtonShadow`. The grip ridges read
// fine against either.
private extension GameBoyPalette {
    var systemButtonShadow: Color { actionButtonShadow }
}
