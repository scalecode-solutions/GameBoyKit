import SwiftUI

/// The full screen unit: recessed maroon bezel, the dead-LCD olive
/// surface inside, "POWER" LED, and the consumer's content view
/// rendered into the LCD area.
internal struct ScreenView<Screen: View, Subtitle: View>: View {
    let palette: GameBoyPalette
    let isPowered: Bool
    @ViewBuilder var screen: () -> Screen
    @ViewBuilder var subtitle: () -> Subtitle

    var body: some View {
        VStack(spacing: 8) {
            // Bezel: LCD centered, POWER LED tucked into the bottom-left.
            // This matches the real DMG layout where the LED sits in the
            // bezel itself, below the screen, freeing the LCD to use the
            // full width of the bezel.
            ZStack(alignment: .bottomLeading) {
                bezel
                lcd
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                powerCorner
                    .padding(.leading, 18)
                    .padding(.bottom, 8)
            }

            // Italic subtitle below ("DOT MATRIX WITH STEREO SOUND")
            subtitle()
                .font(GameBoyTypography.subtitleFont)
                .foregroundStyle(palette.subtitleColor)
                .tracking(0.4)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Pieces

    private var bezel: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [palette.screenBezelEdge, palette.screenBezel],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
    }

    private var powerCorner: some View {
        HStack(spacing: 6) {
            PowerLED(palette: palette, isOn: isPowered)
            Text("POWER")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                // Light tint that reads against the dark bezel — the
                // palette's subtitle color is tuned for the shell, not
                // for being placed on top of the bezel.
                .foregroundStyle(Color.white.opacity(0.62))
                .tracking(0.2)
        }
    }

    private var lcd: some View {
        ZStack {
            // Dead-LCD olive surface
            Rectangle()
                .fill(palette.lcdBackground)
            // Subtle glow when "on"
            if isPowered {
                Rectangle()
                    .fill(
                        RadialGradient(
                            colors: [palette.lcdGlow, .clear],
                            center: .init(x: 0.5, y: 0.4),
                            startRadius: 4,
                            endRadius: 220
                        )
                    )
            }
            // Content
            screen()
                .opacity(isPowered ? 1 : 0.0)
                .animation(.easeInOut(duration: 0.25), value: isPowered)
        }
        // Native Game Boy was 10:9, but the bezel reads better when the
        // LCD leans wider — closer to 4:3 — and the consumer's content
        // doesn't care about exact resolution since this is a mockup.
        .aspectRatio(4.0/3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
        )
    }
}
