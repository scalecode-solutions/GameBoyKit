import SwiftUI

/// SwiftUI environment key carrying the active (already light/dark
/// resolved) `GameBoyPalette`. `GameBoyView` injects this so that any
/// view living inside the LCD — cartridge shelves, games — can read
/// `@Environment(\.gameBoyPalette)` and draw with the right colors,
/// without having to be passed the palette explicitly.
private struct GameBoyPaletteKey: EnvironmentKey {
    static let defaultValue: GameBoyPalette = .dmgMeetsColorLight
}

public extension EnvironmentValues {
    var gameBoyPalette: GameBoyPalette {
        get { self[GameBoyPaletteKey.self] }
        set { self[GameBoyPaletteKey.self] = newValue }
    }
}
