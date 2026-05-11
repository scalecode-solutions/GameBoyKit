import Foundation
import Observation

/// Runtime, user-tweakable device state — the kind of stuff a "system
/// settings" screen on a real handheld would let you change. Owned by
/// `GameBoyView` and injected into the environment so chassis buttons
/// (for haptics gating) and the OS layer (for the device menu UI) all
/// read the same source of truth.
///
/// Lives in GameBoyKit rather than ConsoleKit because the *chassis*
/// needs to read these to gate things like haptic feedback, and the
/// package dependency points downward (GameBoyKit can't import its
/// consumer). ConsoleKit imports GameBoyKit and provides the UI for
/// editing the values.
///
/// Settings persist to `UserDefaults` (standard suite, "gbk." prefix).
/// Tests/previews can pass `persisted: false` to skip persistence.
@MainActor
@Observable
public final class DeviceSettings {

    // MARK: - Properties

    public var hapticsEnabled: Bool {
        didSet { persist() }
    }

    public var paletteSet: GameBoyPaletteSet {
        didSet { persist() }
    }

    // MARK: - Init

    @ObservationIgnored
    private let persisted: Bool

    public init(
        hapticsEnabled: Bool = true,
        paletteSet: GameBoyPaletteSet = .dmgMeetsColor,
        persisted: Bool = true
    ) {
        self.persisted = persisted

        if persisted, let stored = Self.load() {
            self.hapticsEnabled = stored.hapticsEnabled
            self.paletteSet = stored.paletteSet
        } else {
            self.hapticsEnabled = hapticsEnabled
            self.paletteSet = paletteSet
        }
    }

    // MARK: - Persistence

    private static let hapticsKey = "gbk.hapticsEnabled"
    private static let paletteKey = "gbk.paletteSetID"

    private struct StoredValues {
        let hapticsEnabled: Bool
        let paletteSet: GameBoyPaletteSet
    }

    private static func load() -> StoredValues? {
        let defaults = UserDefaults.standard
        // Only treat as "stored" if at least one key has been written.
        guard defaults.object(forKey: hapticsKey) != nil
                || defaults.object(forKey: paletteKey) != nil else {
            return nil
        }
        let haptics = defaults.object(forKey: hapticsKey) as? Bool ?? true
        let id = defaults.string(forKey: paletteKey) ?? "dmgMeetsColor"
        let palette = GameBoyPaletteSet.builtIn(id: id) ?? .dmgMeetsColor
        return StoredValues(hapticsEnabled: haptics, paletteSet: palette)
    }

    private func persist() {
        guard persisted else { return }
        let defaults = UserDefaults.standard
        defaults.set(hapticsEnabled, forKey: Self.hapticsKey)
        defaults.set(paletteSet.builtInID, forKey: Self.paletteKey)
    }
}
