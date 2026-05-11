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
    @Binding private var powerOn: Bool

    // MARK: - Owned state

    @State private var input = GameBoyInput()
    @State private var settings: DeviceSettings
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
        theme: GameBoyTheme = .system,
        persistSettings: Bool = true
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
        // Constructor args seed the DeviceSettings on first launch. Once
        // saved, the persisted values take over and the args are ignored
        // (consumer can pass persistSettings: false to bypass).
        self._settings = State(initialValue: DeviceSettings(
            paletteSet: palette,
            theme: theme,
            persisted: persistSettings
        ))
    }

    /// The concrete palette in effect right now.
    private var resolvedPalette: GameBoyPalette {
        settings.paletteSet.resolve(for: settings.theme, system: systemScheme)
    }

    public var body: some View {
        let palette = resolvedPalette
        return ZStack {
            // Full-bleed face: the host's screen IS the Game Boy.
            // Same shell gradient as before, just painting the
            // available area edge-to-edge instead of a chassis-shaped
            // object floating on a backdrop. No rounded corners, no
            // outer drop shadow — the face is the surface.
            //
            // Only ignore the bottom safe area: the cream paints under
            // the home indicator for an immersive edge-to-edge bleed,
            // but stops cleanly at the top safe-area edge so a host
            // NavigationStack's nav bar (with back chevron) is fully
            // respected and never tinted by the face underneath.
            LinearGradient(
                colors: [palette.shellTop, palette.shellBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)

            content(palette: palette)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        // Cartridges / shelf views inside the screen slot read these.
        .environment(\.gameBoyPalette, palette)
        .environment(\.gameBoyPowerOn, powerOn)
        .environment(\.deviceSettings, settings)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout

    private func content(palette: GameBoyPalette) -> some View {
        VStack(spacing: 0) {
            // Top row: DMG-style power slider on the left, MENU button
            // mod on the right. Sits at the top of the face.
            HStack(alignment: .center) {
                PowerSwitch(isOn: $powerOn, palette: palette)
                Spacer(minLength: 0)
                MenuButton(input: input, palette: palette, label: menuLabel)
            }
            .padding(.bottom, 12)

            // Screen unit (bezel + LCD + power LED + subtitle line)
            ScreenView(
                palette: palette,
                isPowered: powerOn,
                screen:   { screenBuilder(input) },
                subtitle: { subtitleBuilder() }
            )

            // Branding strip: stylized wordmark
            BrandingPlate(palette: palette, headline: headlineBuilder)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)

            // Flex gap — absorbs the extra height on taller phones so the
            // controls naturally sink toward the lower third of the face,
            // within comfortable thumb reach for a one-handed grip.
            Spacer(minLength: 32)

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
            Color.clear.frame(height: 40)

            // Start / Select pair, centered and angled
            SystemButtons(
                palette: palette,
                input: input,
                startLabel: startLabel,
                selectLabel: selectLabel
            )
            .frame(maxWidth: .infinity, alignment: .center)

            // Flex gap — pushes the brand strip to the bottom edge of the face.
            Spacer(minLength: 20)

            // Bottom row: brand on the left, speaker grille on the right.
            // Kept as a corner accent — the grille reads as "Game Boy"
            // without needing a physical chassis curve to host it.
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
