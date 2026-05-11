import SwiftUI

/// Font roles used by the chrome of `GameBoyView`. We deliberately avoid
/// shipping a custom font with the package — the chrome reads as
/// "vintage handheld" with system fonts in the right weights and
/// tracking, and consumers stay free to override anything via the
/// view-builder slots.
internal enum GameBoyTypography {

    /// Big slanted headline above the screen (where "GAME BOY" sits).
    static func headline(_ palette: GameBoyPalette) -> some View {
        EmptyView()
            .modifier(HeadlineStyle(palette: palette))
    }

    static var headlineFont: Font {
        .system(size: 24, weight: .black, design: .rounded).italic()
    }

    static var subtitleFont: Font {
        .system(size: 9, weight: .semibold, design: .serif).italic()
    }

    static var brandFont: Font {
        .system(size: 11, weight: .heavy, design: .rounded).italic()
    }

    static var buttonLabelFont: Font {
        .system(size: 12, weight: .heavy, design: .rounded)
    }

    static var systemButtonLabelFont: Font {
        .system(size: 9, weight: .bold, design: .rounded)
    }
}

private struct HeadlineStyle: ViewModifier {
    let palette: GameBoyPalette
    func body(content: Content) -> some View {
        content
            .font(GameBoyTypography.headlineFont)
            .foregroundStyle(palette.headlineColor)
            .tracking(1)
    }
}
