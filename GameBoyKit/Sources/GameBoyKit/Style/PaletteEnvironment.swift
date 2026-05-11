import SwiftUI

/// SwiftUI environment key carrying the active (already light/dark
/// resolved) `GameBoyPalette`. `GameBoyView` injects this so that any
/// view living inside the LCD — cartridge shelves, games — can read
/// `@Environment(\.gameBoyPalette)` and draw with the right colors,
/// without having to be passed the palette explicitly.
private struct GameBoyPaletteKey: EnvironmentKey {
    static let defaultValue: GameBoyPalette = .dmgMeetsColorLight
}

private struct GameBoyPowerOnKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

public extension EnvironmentValues {
    var gameBoyPalette: GameBoyPalette {
        get { self[GameBoyPaletteKey.self] }
        set { self[GameBoyPaletteKey.self] = newValue }
    }

    /// True while the console is powered on. Cartridges should pause
    /// tick loops and ignore input when this is `false`. `GameBoyView`
    /// injects the resolved value, so any descendant view can read it
    /// with `@Environment(\.gameBoyPowerOn)`.
    var gameBoyPowerOn: Bool {
        get { self[GameBoyPowerOnKey.self] }
        set { self[GameBoyPowerOnKey.self] = newValue }
    }
}
