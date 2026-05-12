import Foundation

/// Shared persistence service for per-cartridge × per-mode best
/// scores. Backed by `UserDefaults` so values survive app restarts.
///
/// Cartridges record their final score after each run and read back
/// the all-time best for the current mode to display on mode-select
/// briefings and game-over banners.
///
/// The API is intentionally static — there's only one UserDefaults
/// store per app instance, and shoving the service onto a singleton
/// avoids threading injection through every cartridge state init.
/// Tests can pass an isolated `UserDefaults(suiteName:)` to keep
/// reads/writes contained.
public enum CartridgeScores {

    /// All stored keys share this prefix so a `reset()` call (or
    /// debug tooling) can find and clear them without touching
    /// unrelated UserDefaults values.
    public static let keyPrefix = "gameboykit.score."

    /// Best score recorded for `cartridge` × `mode`. Returns 0 when
    /// no score has been stored yet (matches `UserDefaults.integer`'s
    /// default-zero behavior).
    public static func best(
        cartridge: String,
        mode: String,
        in defaults: UserDefaults = .standard
    ) -> Int {
        defaults.integer(forKey: key(cartridge: cartridge, mode: mode))
    }

    /// Records `score` as the new best if it exceeds the existing
    /// stored value. Returns `true` when the record was actually
    /// updated — callers use this to flash a "NEW BEST!" indicator.
    @discardableResult
    public static func recordIfBetter(
        _ score: Int,
        cartridge: String,
        mode: String,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        let k = key(cartridge: cartridge, mode: mode)
        let current = defaults.integer(forKey: k)
        guard score > current else { return false }
        defaults.set(score, forKey: k)
        return true
    }

    /// Clears all stored scores. Test seam (pass an isolated
    /// UserDefaults to keep production data untouched).
    public static func reset(in defaults: UserDefaults = .standard) {
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: k)
        }
    }

    // MARK: - Internals

    private static func key(cartridge: String, mode: String) -> String {
        // The cartridge and mode strings are caller-controlled so we
        // normalize whitespace + casing to avoid accidental key
        // explosions if someone passes "Classic" vs "classic" etc.
        let c = cartridge.lowercased()
        let m = mode.lowercased()
        return "\(keyPrefix)\(c).\(m)"
    }
}
