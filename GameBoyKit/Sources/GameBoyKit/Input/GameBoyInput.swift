import Foundation
import Observation

/// Live input state exposed to the game running inside `GameBoyView`.
///
/// Consumers read the `@Observable` properties (`aPressed`, `dpad`, …)
/// for "is held right now" logic, or subscribe to `events` for an
/// edge-triggered stream of presses and releases.
///
/// `GameBoyView` owns and mutates this object; the game closure
/// receives it as an argument and should treat it as read-only.
@MainActor
@Observable
public final class GameBoyInput {

    // MARK: - State (read-only from the consumer's perspective)

    public internal(set) var dpad: DPadDirection? = nil
    public internal(set) var aPressed: Bool = false
    public internal(set) var bPressed: Bool = false
    public internal(set) var startPressed: Bool = false
    public internal(set) var selectPressed: Bool = false

    // MARK: - Event stream

    /// Edge-triggered button events. Multiple subscribers are supported;
    /// each gets its own independent stream of future events.
    public var events: AsyncStream<ButtonEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    @ObservationIgnored
    private var continuations: [UUID: AsyncStream<ButtonEvent>.Continuation] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Mutation (internal — driven by the controls)

    /// Whether a given button is currently held.
    public func isPressed(_ button: GameBoyButton) -> Bool {
        switch button {
        case .dpadUp:    return dpad?.isUp    ?? false
        case .dpadDown:  return dpad?.isDown  ?? false
        case .dpadLeft:  return dpad?.isLeft  ?? false
        case .dpadRight: return dpad?.isRight ?? false
        case .a:         return aPressed
        case .b:         return bPressed
        case .start:     return startPressed
        case .select:    return selectPressed
        }
    }

    /// Update the D-pad. Emits press/release events for each axis that
    /// changed from held → not-held or vice versa.
    internal func setDPad(_ next: DPadDirection?) {
        let previous = dpad
        guard previous != next else { return }
        dpad = next
        emitAxisDelta(previous: previous, next: next)
    }

    /// Set the held state of a face/system button, emitting an event
    /// only if the state actually changed.
    internal func setButton(_ button: GameBoyButton, pressed: Bool) {
        switch button {
        case .a:      guard aPressed      != pressed else { return }; aPressed      = pressed
        case .b:      guard bPressed      != pressed else { return }; bPressed      = pressed
        case .start:  guard startPressed  != pressed else { return }; startPressed  = pressed
        case .select: guard selectPressed != pressed else { return }; selectPressed = pressed
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
            // D-pad axes can't be set independently; use `setDPad`.
            return
        }
        emit(.init(button: button, phase: pressed ? .pressed : .released))
    }

    private func emitAxisDelta(previous: DPadDirection?, next: DPadDirection?) {
        let wasUp    = previous?.isUp    ?? false; let isUp_    = next?.isUp    ?? false
        let wasDown  = previous?.isDown  ?? false; let isDown_  = next?.isDown  ?? false
        let wasLeft  = previous?.isLeft  ?? false; let isLeft_  = next?.isLeft  ?? false
        let wasRight = previous?.isRight ?? false; let isRight_ = next?.isRight ?? false

        if wasUp    != isUp_    { emit(.init(button: .dpadUp,    phase: isUp_    ? .pressed : .released)) }
        if wasDown  != isDown_  { emit(.init(button: .dpadDown,  phase: isDown_  ? .pressed : .released)) }
        if wasLeft  != isLeft_  { emit(.init(button: .dpadLeft,  phase: isLeft_  ? .pressed : .released)) }
        if wasRight != isRight_ { emit(.init(button: .dpadRight, phase: isRight_ ? .pressed : .released)) }
    }

    private func emit(_ event: ButtonEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}
