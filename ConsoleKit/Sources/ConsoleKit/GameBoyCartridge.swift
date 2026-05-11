import SwiftUI
import GameBoyKit

/// A "cartridge" represents one game that can be loaded into the
/// console. It's a value type holding metadata for the menu plus a
/// factory closure that builds the gameplay view when the user picks it.
///
/// ## Building one
/// ```swift
/// let snake = GameBoyCartridge(
///     id: "snake",
///     title: "SNAKE",
///     blurb: "EAT. GROW. AVOID YOURSELF.",
///     make: { input in SnakeGame(input: input) }
/// )
/// ```
public struct GameBoyCartridge: Identifiable, Sendable {

    /// Stable identifier used for menu selection state and equality.
    public let id: String

    /// Short title displayed in the menu (typically all-caps, ≤10 chars).
    public let title: String

    /// One-line description shown beside the highlighted menu row.
    public let blurb: String

    /// Builds the gameplay view, given the live `GameBoyInput`.
    public let make: @MainActor (GameBoyInput) -> AnyView

    public init<Content: View>(
        id: String,
        title: String,
        blurb: String = "",
        @ViewBuilder make: @escaping @MainActor (GameBoyInput) -> Content
    ) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.make = { input in AnyView(make(input)) }
    }
}

extension GameBoyCartridge: Equatable {
    public static func == (lhs: GameBoyCartridge, rhs: GameBoyCartridge) -> Bool {
        lhs.id == rhs.id
    }
}
