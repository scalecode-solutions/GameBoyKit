import SwiftUI

/// A non-functional UI mockup of a Game Boy that hosts arbitrary
/// SwiftUI content as its "screen" and surfaces button presses via a
/// `GameBoyInput` instance the consumer can read in their game.
///
/// ## Slots
/// - `screen`   *(required)* — the view rendered inside the LCD.
///   Receives the live `GameBoyInput` so it can react to input.
/// - `headline` — large slanted text where "GAME BOY" sits.
/// - `subtitle` — italic line below the screen.
/// - `brand`    — small mark in the bottom-right of the shell.
///
/// ## Example
/// ```swift
/// GameBoyView(
///     screen:   { input in MyGameView(input: input) },
///     headline: { Text("CLINGY BOY") },
///     subtitle: { Text("DOT MATRIX • TAP TO PLAY") },
///     brand:    { Text("travis ®") },
///     aLabel: "A", bLabel: "B",
///     startLabel: "START", selectLabel: "SELECT"
/// )
/// ```
public struct GameBoyView<Screen: View, Headline: View, Subtitle: View, Brand: View>: View {

    // MARK: - Slots

    private let screenBuilder: (GameBoyInput) -> Screen
    private let headlineBuilder: () -> Headline
    private let subtitleBuilder: () -> Subtitle
    private let brandBuilder: () -> Brand

    // MARK: - Config

    private let aLabel: String
    private let bLabel: String
    private let startLabel: String
    private let selectLabel: String
    private let menuLabel: String
    private let palette: GameBoyPaletteSet
    private let theme: GameBoyTheme
    @Binding private var powerOn: Bool

    // MARK: - Owned state

    @State private var input = GameBoyInput()
    @Environment(\.colorScheme) private var systemScheme

    public init(
        @ViewBuilder screen:   @escaping (GameBoyInput) -> Screen,
        @ViewBuilder headline: @escaping () -> Headline  = { EmptyView() },
        @ViewBuilder subtitle: @escaping () -> Subtitle  = { EmptyView() },
        @ViewBuilder brand:    @escaping () -> Brand     = { EmptyView() },
        aLabel: String = "A",
        bLabel: String = "B",
        startLabel: String  = "START",
        selectLabel: String = "SELECT",
        menuLabel: String = "MENU",
        powerOn: Binding<Bool> = .constant(true),
        palette: GameBoyPaletteSet = .dmgMeetsColor,
        theme: GameBoyTheme = .system
    ) {
        self.screenBuilder   = screen
        self.headlineBuilder = headline
        self.subtitleBuilder = subtitle
        self.brandBuilder    = brand
        self.aLabel = aLabel
        self.bLabel = bLabel
        self.startLabel = startLabel
        self.selectLabel = selectLabel
        self.menuLabel = menuLabel
        self._powerOn = powerOn
        self.palette = palette
        self.theme = theme
    }

    /// The concrete palette in effect right now.
    private var resolvedPalette: GameBoyPalette {
        palette.resolve(for: theme, system: systemScheme)
    }

    public var body: some View {
        let palette = resolvedPalette
        return ZStack {
            ShellBackground(palette: palette)
            content(palette: palette)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
        }
        // Cartridges / shelf views inside the screen slot read these.
        .environment(\.gameBoyPalette, palette)
        .environment(\.gameBoyPowerOn, powerOn)
        // We run noticeably taller than the real DMG (~0.61) so that
        // the controls sit closer to the bottom of the device — that
        // puts the D-pad and A/B in natural thumb territory when the
        // user is holding the phone, instead of forcing a reach up.
        .aspectRatio(0.52, contentMode: .fit)
        .frame(maxWidth: 520)                         // looks right on phone & iPad
    }

    // MARK: - Layout

    private func content(palette: GameBoyPalette) -> some View {
        VStack(spacing: 0) {
            // Top row: DMG-style power slider on the left, MENU button
            // mod on the right. Lives on the chassis itself so the
            // device is fully self-contained.
            HStack(alignment: .center) {
                PowerSwitch(isOn: $powerOn, palette: palette)
                Spacer(minLength: 0)
                MenuButton(input: input, palette: palette, label: menuLabel)
            }
            .padding(.bottom, 6)

            // Screen unit (bezel + LCD + power LED + subtitle line)
            ScreenView(
                palette: palette,
                isPowered: powerOn,
                screen:   { screenBuilder(input) },
                subtitle: { subtitleBuilder() }
            )

            // Branding strip: stylized "GAME BOY" headline
            BrandingPlate(palette: palette, headline: headlineBuilder)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)

            // Explicit screen-to-controls gap (was a flexible Spacer).
            // The extra height from the taller chassis lands here, so
            // the controls visibly sit lower on the device — within
            // comfortable thumb reach for a one-handed grip.
            Spacer(minLength: 48)

            // Controls row: D-pad on the left, A/B on the right.
            // D-pad is sized for fat-finger UX — virtual D-pads need
            // to be bigger than their hardware analog because there's
            // no tactile cross to feel for, so each direction needs to
            // be comfortably wider than a fingertip contact patch.
            HStack(alignment: .center) {
                DPad(palette: palette, input: input)
                    .frame(width: 140, height: 140)
                Spacer(minLength: 0)
                ActionButtons(
                    palette: palette,
                    input: input,
                    aLabel: aLabel,
                    bLabel: bLabel
                )
            }
            .padding(.horizontal, 6)

            // Fixed gap so the tilted START pill clears the B button.
            // Flexible spacers split the remaining slack 50/50.
            Color.clear.frame(height: 40)

            // Start / Select pair, centered and angled
            SystemButtons(
                palette: palette,
                input: input,
                startLabel: startLabel,
                selectLabel: selectLabel
            )
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 16)

            // Bottom row: brand on the left, speaker grille on the right
            HStack(alignment: .center) {
                brandBuilder()
                    .font(GameBoyTypography.brandFont)
                    .foregroundStyle(palette.brandColor)
                    .tracking(0.8)
                Spacer()
                SpeakerGrille(palette: palette)
                    .frame(width: 90, height: 60)
            }
            .padding(.horizontal, 6)
        }
    }
}
