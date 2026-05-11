import SwiftUI

/// Color palette controlling every tintable surface of `GameBoyView`.
/// Use `GameBoyPaletteSet` to pair a light and a dark variant; that's
/// what the public `GameBoyView` API accepts. This struct is exposed
/// so you can hand-roll a custom palette and inject it into a set.
public struct GameBoyPalette: Sendable, Equatable {

    // Shell
    public var shellTop: Color
    public var shellBottom: Color
    public var shellEdgeHighlight: Color
    public var shellEdgeShadow: Color

    // Screen bezel
    public var screenBezel: Color
    public var screenBezelEdge: Color

    // LCD
    public var lcdBackground: Color    // dead-pixel olive
    public var lcdGlow: Color          // subtle radial tint when "on"

    // Classic 4-shade DMG color ramp for in-LCD pixel drawing.
    // Shade 0 is the lightest (typically the background), shade 3 is darkest.
    public var lcdShade0: Color
    public var lcdShade1: Color
    public var lcdShade2: Color
    public var lcdShade3: Color

    // Power LED
    public var ledOn: Color
    public var ledOff: Color
    public var ledRing: Color

    // Action buttons (A / B)
    public var actionButton: Color
    public var actionButtonHighlight: Color
    public var actionButtonShadow: Color
    public var actionButtonLabel: Color

    // System buttons (Start / Select)
    public var systemButton: Color
    public var systemButtonHighlight: Color
    public var systemButtonLabel: Color

    // D-pad
    public var dpad: Color
    public var dpadHighlight: Color
    public var dpadShadow: Color

    // Typography
    public var headlineColor: Color
    public var subtitleColor: Color
    public var brandColor: Color
    public var speakerGrilleColor: Color

    public init(
        shellTop: Color,
        shellBottom: Color,
        shellEdgeHighlight: Color,
        shellEdgeShadow: Color,
        screenBezel: Color,
        screenBezelEdge: Color,
        lcdBackground: Color,
        lcdGlow: Color,
        lcdShade0: Color,
        lcdShade1: Color,
        lcdShade2: Color,
        lcdShade3: Color,
        ledOn: Color,
        ledOff: Color,
        ledRing: Color,
        actionButton: Color,
        actionButtonHighlight: Color,
        actionButtonShadow: Color,
        actionButtonLabel: Color,
        systemButton: Color,
        systemButtonHighlight: Color,
        systemButtonLabel: Color,
        dpad: Color,
        dpadHighlight: Color,
        dpadShadow: Color,
        headlineColor: Color,
        subtitleColor: Color,
        brandColor: Color,
        speakerGrilleColor: Color
    ) {
        self.shellTop = shellTop
        self.shellBottom = shellBottom
        self.shellEdgeHighlight = shellEdgeHighlight
        self.shellEdgeShadow = shellEdgeShadow
        self.screenBezel = screenBezel
        self.screenBezelEdge = screenBezelEdge
        self.lcdBackground = lcdBackground
        self.lcdGlow = lcdGlow
        self.lcdShade0 = lcdShade0
        self.lcdShade1 = lcdShade1
        self.lcdShade2 = lcdShade2
        self.lcdShade3 = lcdShade3
        self.ledOn = ledOn
        self.ledOff = ledOff
        self.ledRing = ledRing
        self.actionButton = actionButton
        self.actionButtonHighlight = actionButtonHighlight
        self.actionButtonShadow = actionButtonShadow
        self.actionButtonLabel = actionButtonLabel
        self.systemButton = systemButton
        self.systemButtonHighlight = systemButtonHighlight
        self.systemButtonLabel = systemButtonLabel
        self.dpad = dpad
        self.dpadHighlight = dpadHighlight
        self.dpadShadow = dpadShadow
        self.headlineColor = headlineColor
        self.subtitleColor = subtitleColor
        self.brandColor = brandColor
        self.speakerGrilleColor = speakerGrilleColor
    }
}

// MARK: - Built-in light palettes

public extension GameBoyPalette {

    /// DMG silhouette × Game Boy Color palette — cream shell, berry buttons.
    static let dmgMeetsColorLight = GameBoyPalette(
        shellTop:              Color(red: 0.96, green: 0.93, blue: 0.88),
        shellBottom:           Color(red: 0.90, green: 0.86, blue: 0.79),
        shellEdgeHighlight:    Color.white.opacity(0.55),
        shellEdgeShadow:       Color.black.opacity(0.18),

        screenBezel:           Color(red: 0.36, green: 0.14, blue: 0.22),
        screenBezelEdge:       Color(red: 0.20, green: 0.06, blue: 0.12),

        lcdBackground:         Color(red: 0.55, green: 0.62, blue: 0.43),
        lcdGlow:               Color(red: 0.78, green: 0.83, blue: 0.55).opacity(0.35),
        lcdShade0:             Color(red: 0.60, green: 0.66, blue: 0.46),
        lcdShade1:             Color(red: 0.46, green: 0.52, blue: 0.32),
        lcdShade2:             Color(red: 0.27, green: 0.32, blue: 0.18),
        lcdShade3:             Color(red: 0.10, green: 0.14, blue: 0.06),

        ledOn:                 Color(red: 0.92, green: 0.18, blue: 0.18),
        ledOff:                Color(red: 0.40, green: 0.10, blue: 0.10),
        ledRing:               Color.black.opacity(0.45),

        actionButton:          Color(red: 0.55, green: 0.18, blue: 0.42),
        actionButtonHighlight: Color(red: 0.78, green: 0.45, blue: 0.68),
        actionButtonShadow:    Color(red: 0.30, green: 0.06, blue: 0.22),
        actionButtonLabel:     Color(red: 0.20, green: 0.04, blue: 0.14),

        systemButton:          Color(red: 0.52, green: 0.52, blue: 0.55),
        systemButtonHighlight: Color(red: 0.78, green: 0.78, blue: 0.82),
        systemButtonLabel:     Color(red: 0.30, green: 0.18, blue: 0.32),

        dpad:                  Color(red: 0.16, green: 0.18, blue: 0.22),
        dpadHighlight:         Color(red: 0.34, green: 0.38, blue: 0.44),
        dpadShadow:            Color.black.opacity(0.55),

        headlineColor:         Color(red: 0.20, green: 0.06, blue: 0.20),
        subtitleColor:         Color(red: 0.36, green: 0.14, blue: 0.30),
        brandColor:            Color(red: 0.28, green: 0.10, blue: 0.24),
        speakerGrilleColor:    Color(red: 0.55, green: 0.50, blue: 0.46)
    )

    /// Classic DMG: cool gray shell, dark gray buttons. Light variant.
    static let classicDMGLight = GameBoyPalette(
        shellTop:              Color(red: 0.82, green: 0.83, blue: 0.83),
        shellBottom:           Color(red: 0.72, green: 0.74, blue: 0.74),
        shellEdgeHighlight:    Color.white.opacity(0.50),
        shellEdgeShadow:       Color.black.opacity(0.20),

        screenBezel:           Color(red: 0.30, green: 0.31, blue: 0.32),
        screenBezelEdge:       Color(red: 0.15, green: 0.16, blue: 0.17),

        lcdBackground:         Color(red: 0.55, green: 0.62, blue: 0.43),
        lcdGlow:               Color(red: 0.78, green: 0.83, blue: 0.55).opacity(0.30),
        lcdShade0:             Color(red: 0.60, green: 0.66, blue: 0.46),
        lcdShade1:             Color(red: 0.46, green: 0.52, blue: 0.32),
        lcdShade2:             Color(red: 0.27, green: 0.32, blue: 0.18),
        lcdShade3:             Color(red: 0.10, green: 0.14, blue: 0.06),

        ledOn:                 Color(red: 0.92, green: 0.18, blue: 0.18),
        ledOff:                Color(red: 0.40, green: 0.10, blue: 0.10),
        ledRing:               Color.black.opacity(0.45),

        actionButton:          Color(red: 0.62, green: 0.12, blue: 0.30),
        actionButtonHighlight: Color(red: 0.85, green: 0.30, blue: 0.45),
        actionButtonShadow:    Color(red: 0.32, green: 0.04, blue: 0.14),
        actionButtonLabel:     Color(red: 0.18, green: 0.18, blue: 0.20),

        systemButton:          Color(red: 0.42, green: 0.44, blue: 0.46),
        systemButtonHighlight: Color(red: 0.68, green: 0.70, blue: 0.72),
        systemButtonLabel:     Color(red: 0.20, green: 0.20, blue: 0.22),

        dpad:                  Color(red: 0.12, green: 0.13, blue: 0.14),
        dpadHighlight:         Color(red: 0.28, green: 0.30, blue: 0.32),
        dpadShadow:            Color.black.opacity(0.55),

        headlineColor:         Color(red: 0.15, green: 0.16, blue: 0.18),
        subtitleColor:         Color(red: 0.30, green: 0.32, blue: 0.34),
        brandColor:            Color(red: 0.20, green: 0.22, blue: 0.24),
        speakerGrilleColor:    Color(red: 0.50, green: 0.52, blue: 0.54)
    )
}

// MARK: - Built-in dark palettes

public extension GameBoyPalette {

    /// "Midnight Berry" — DMG silhouette with deep indigo shell and
    /// neon berry buttons. Designed to pair with `dmgMeetsColorLight`.
    static let dmgMeetsColorDark = GameBoyPalette(
        shellTop:              Color(red: 0.20, green: 0.17, blue: 0.26),
        shellBottom:           Color(red: 0.13, green: 0.11, blue: 0.18),
        shellEdgeHighlight:    Color.white.opacity(0.12),
        shellEdgeShadow:       Color.black.opacity(0.60),

        screenBezel:           Color(red: 0.18, green: 0.06, blue: 0.16),
        screenBezelEdge:       Color(red: 0.08, green: 0.02, blue: 0.08),

        lcdBackground:         Color(red: 0.45, green: 0.55, blue: 0.32),
        lcdGlow:               Color(red: 0.65, green: 0.78, blue: 0.42).opacity(0.40),
        lcdShade0:             Color(red: 0.52, green: 0.62, blue: 0.36),
        lcdShade1:             Color(red: 0.38, green: 0.46, blue: 0.24),
        lcdShade2:             Color(red: 0.22, green: 0.28, blue: 0.14),
        lcdShade3:             Color(red: 0.08, green: 0.12, blue: 0.04),

        ledOn:                 Color(red: 1.00, green: 0.30, blue: 0.30),
        ledOff:                Color(red: 0.30, green: 0.06, blue: 0.06),
        ledRing:               Color.black.opacity(0.55),

        actionButton:          Color(red: 0.78, green: 0.30, blue: 0.62),
        actionButtonHighlight: Color(red: 1.00, green: 0.55, blue: 0.85),
        actionButtonShadow:    Color(red: 0.30, green: 0.06, blue: 0.20),
        actionButtonLabel:     Color(red: 0.92, green: 0.88, blue: 0.95),

        systemButton:          Color(red: 0.50, green: 0.48, blue: 0.55),
        systemButtonHighlight: Color(red: 0.72, green: 0.70, blue: 0.78),
        systemButtonLabel:     Color(red: 0.85, green: 0.82, blue: 0.90),

        dpad:                  Color(red: 0.42, green: 0.45, blue: 0.52),
        dpadHighlight:         Color(red: 0.60, green: 0.62, blue: 0.68),
        dpadShadow:            Color.black.opacity(0.65),

        headlineColor:         Color(red: 0.96, green: 0.92, blue: 0.86),
        subtitleColor:         Color(red: 0.78, green: 0.72, blue: 0.82),
        brandColor:            Color(red: 0.85, green: 0.80, blue: 0.90),
        speakerGrilleColor:    Color(red: 0.45, green: 0.42, blue: 0.50)
    )

    /// "Charcoal DMG" — neutral dark variant of the classic gray
    /// palette. Designed to pair with `classicDMGLight`.
    static let classicDMGDark = GameBoyPalette(
        shellTop:              Color(red: 0.20, green: 0.20, blue: 0.22),
        shellBottom:           Color(red: 0.14, green: 0.14, blue: 0.16),
        shellEdgeHighlight:    Color.white.opacity(0.10),
        shellEdgeShadow:       Color.black.opacity(0.60),

        screenBezel:           Color(red: 0.10, green: 0.10, blue: 0.11),
        screenBezelEdge:       Color(red: 0.04, green: 0.04, blue: 0.05),

        lcdBackground:         Color(red: 0.45, green: 0.55, blue: 0.32),
        lcdGlow:               Color(red: 0.65, green: 0.78, blue: 0.42).opacity(0.40),
        lcdShade0:             Color(red: 0.52, green: 0.62, blue: 0.36),
        lcdShade1:             Color(red: 0.38, green: 0.46, blue: 0.24),
        lcdShade2:             Color(red: 0.22, green: 0.28, blue: 0.14),
        lcdShade3:             Color(red: 0.08, green: 0.12, blue: 0.04),

        ledOn:                 Color(red: 1.00, green: 0.25, blue: 0.25),
        ledOff:                Color(red: 0.30, green: 0.06, blue: 0.06),
        ledRing:               Color.black.opacity(0.55),

        actionButton:          Color(red: 0.72, green: 0.15, blue: 0.32),
        actionButtonHighlight: Color(red: 0.95, green: 0.40, blue: 0.55),
        actionButtonShadow:    Color(red: 0.30, green: 0.04, blue: 0.10),
        actionButtonLabel:     Color(red: 0.92, green: 0.88, blue: 0.88),

        systemButton:          Color(red: 0.50, green: 0.50, blue: 0.52),
        systemButtonHighlight: Color(red: 0.72, green: 0.72, blue: 0.74),
        systemButtonLabel:     Color(red: 0.80, green: 0.80, blue: 0.82),

        dpad:                  Color(red: 0.42, green: 0.43, blue: 0.44),
        dpadHighlight:         Color(red: 0.60, green: 0.61, blue: 0.62),
        dpadShadow:            Color.black.opacity(0.65),

        headlineColor:         Color(red: 0.92, green: 0.92, blue: 0.92),
        subtitleColor:         Color(red: 0.75, green: 0.75, blue: 0.78),
        brandColor:            Color(red: 0.82, green: 0.82, blue: 0.84),
        speakerGrilleColor:    Color(red: 0.50, green: 0.50, blue: 0.52)
    )
}

// MARK: - Paired light + dark sets

/// A pair of palettes — one for light mode, one for dark — that
/// `GameBoyView` resolves against the current `colorScheme` (or a
/// forced `GameBoyTheme`).
public struct GameBoyPaletteSet: Sendable, Equatable {
    public var light: GameBoyPalette
    public var dark: GameBoyPalette

    public init(light: GameBoyPalette, dark: GameBoyPalette) {
        self.light = light
        self.dark = dark
    }

    /// Convenience initializer for consumers who want the same palette
    /// in both modes (no theming).
    public init(_ palette: GameBoyPalette) {
        self.light = palette
        self.dark = palette
    }

    func resolve(for theme: GameBoyTheme, system: ColorScheme) -> GameBoyPalette {
        theme.resolve(system: system) == .dark ? dark : light
    }
}

public extension GameBoyPaletteSet {
    /// DMG silhouette × Game Boy Color, themed light/dark.
    static let dmgMeetsColor = GameBoyPaletteSet(
        light: .dmgMeetsColorLight,
        dark:  .dmgMeetsColorDark
    )

    /// Classic gray DMG, themed light/dark.
    static let classicDMG = GameBoyPaletteSet(
        light: .classicDMGLight,
        dark:  .classicDMGDark
    )

    /// All built-in sets, in the order they appear in the device menu's
    /// theme picker.
    static let builtIns: [(id: String, name: String, set: GameBoyPaletteSet)] = [
        ("dmgMeetsColor", "DMG × COLOR", .dmgMeetsColor),
        ("classicDMG",    "CLASSIC DMG", .classicDMG)
    ]

    /// Look up a built-in set by its stable id.
    static func builtIn(id: String) -> GameBoyPaletteSet? {
        builtIns.first(where: { $0.id == id })?.set
    }

    /// Returns the built-in id of this set if it matches one of the
    /// built-ins by value, else `nil` (custom palette).
    var builtInID: String? {
        Self.builtIns.first(where: { $0.set == self })?.id
    }

    /// User-facing name for this set if it's a built-in, else "CUSTOM".
    var displayName: String {
        Self.builtIns.first(where: { $0.set == self })?.name ?? "CUSTOM"
    }
}
