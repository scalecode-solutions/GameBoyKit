import Foundation

/// Every distinct button on the Game Boy face. D-pad directions are
/// represented as four `dpad*` cases; diagonals are reported via
/// `GameBoyInput.dpad` but not surfaced as separate buttons since you
/// can't trigger a diagonal independently of its component axes.
public enum GameBoyButton: String, CaseIterable, Sendable, Hashable {
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case a, b
    case start, select
}

/// Edge-triggered event delivered via `GameBoyInput.events`. Use for
/// "fired on press" logic; for "is currently held" logic, read the
/// `@Observable` state on `GameBoyInput` directly.
public struct ButtonEvent: Sendable, Hashable {
    public enum Phase: Sendable, Hashable { case pressed, released }

    public let button: GameBoyButton
    public let phase: Phase
    public let timestamp: Date

    public init(button: GameBoyButton, phase: Phase, timestamp: Date = .init()) {
        self.button = button
        self.phase = phase
        self.timestamp = timestamp
    }
}
