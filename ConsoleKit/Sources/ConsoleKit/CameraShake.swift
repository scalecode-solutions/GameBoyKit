import Foundation

/// Tiny screen-shake helper. A cartridge's state holds one of these
/// and calls `trigger` on impact events (crash, hard landing, etc.);
/// each tick advances it and decays the amplitude; the view reads
/// `offsetX` / `offsetY` and applies them via SwiftUI's `.offset`
/// modifier on the `PixelCanvas`.
///
/// Value type so it nests cleanly inside `@Observable` state classes
/// without owning a separate observation lifecycle. All mutation
/// happens on the main actor (via the owning state's `@MainActor`
/// isolation).
public struct CameraShake: Sendable {

    public private(set) var offsetX: Int = 0
    public private(set) var offsetY: Int = 0

    private var ticksRemaining: Int = 0
    private var amplitude: Double = 0
    private let decayPerTick: Double

    /// `decay` is the per-tick multiplier on amplitude — values close
    /// to 1.0 make the shake linger; values closer to 0.8 snap out
    /// quickly. Default 0.86 (≈12% per tick) gives a satisfying
    /// "thud → settle" curve over the default 14-tick duration.
    public init(decay: Double = 0.86) {
        self.decayPerTick = decay
    }

    /// Start (or strengthen) a shake. The fresh values take effect on
    /// the same frame so the next render shows a non-zero offset.
    ///
    /// - Parameters:
    ///   - amplitude: peak offset radius in logical points
    ///   - ticks: how long the shake runs at 60Hz
    public mutating func trigger(amplitude: Double = 3.5, ticks: Int = 14) {
        self.amplitude = max(self.amplitude, amplitude)
        self.ticksRemaining = max(self.ticksRemaining, ticks)
        regenerateOffset()
    }

    /// Advance one tick — decays the amplitude and picks a fresh
    /// random offset within the current radius. Becomes a no-op once
    /// `ticksRemaining` hits zero.
    public mutating func tick() {
        guard ticksRemaining > 0 else {
            if offsetX != 0 || offsetY != 0 {
                offsetX = 0
                offsetY = 0
            }
            return
        }
        ticksRemaining -= 1
        amplitude *= decayPerTick
        regenerateOffset()
    }

    /// True while the shake is producing a visible offset.
    public var isActive: Bool { ticksRemaining > 0 }

    // MARK: - Internals

    private mutating func regenerateOffset() {
        guard amplitude >= 0.5 else {
            offsetX = 0
            offsetY = 0
            return
        }
        let r = Int(amplitude.rounded())
        offsetX = Int.random(in: -r...r)
        offsetY = Int.random(in: -r...r)
    }
}
