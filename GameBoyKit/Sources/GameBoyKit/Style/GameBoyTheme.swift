import SwiftUI

/// How a `GameBoyView` should pick between its light and dark
/// palettes. The default is `.system`, which follows the parent
/// view's `@Environment(\.colorScheme)`.
public enum GameBoyTheme: String, Sendable, Equatable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    public var id: String { rawValue }
}

extension GameBoyTheme {
    /// Resolve to a concrete `ColorScheme` using the supplied system scheme
    /// when the theme is `.system`.
    func resolve(system: ColorScheme) -> ColorScheme {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return system
        }
    }
}
