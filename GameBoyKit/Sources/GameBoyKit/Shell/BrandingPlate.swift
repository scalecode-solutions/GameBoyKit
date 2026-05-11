import SwiftUI

/// The headline plate that sits below the screen bezel — where the
/// original DMG's stylized "GAME BOY" wordmark lives. Renders whatever
/// view the consumer supplies for the `headline` slot, with the
/// `™` decorative mark to its right (consumer-suppressible by hiding
/// it with an empty `headline`).
internal struct BrandingPlate<Headline: View>: View {
    let palette: GameBoyPalette
    @ViewBuilder var headline: () -> Headline

    var body: some View {
        HStack(spacing: 4) {
            headline()
                .font(GameBoyTypography.headlineFont)
                .foregroundStyle(palette.headlineColor)
                .tracking(1)
            // The little superscript ™ that lives next to "GAME BOY" on the
            // real device. Decorative only.
            Text("™")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.headlineColor.opacity(0.8))
                .offset(y: -8)
        }
        .padding(.vertical, 2)
    }
}
