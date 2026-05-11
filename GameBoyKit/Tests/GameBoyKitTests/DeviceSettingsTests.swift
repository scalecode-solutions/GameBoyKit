import Testing
import Foundation
@testable import GameBoyKit

@MainActor
struct DeviceSettingsTests {

    @Test func defaultsAreOnAndDmgMeetsColor() {
        let settings = DeviceSettings(persisted: false)
        #expect(settings.hapticsEnabled == true)
        #expect(settings.paletteSet == .dmgMeetsColor)
    }

    @Test func overridesAreRespectedWhenNotPersisted() {
        let settings = DeviceSettings(
            hapticsEnabled: false,
            paletteSet: .classicDMG,
            persisted: false
        )
        #expect(settings.hapticsEnabled == false)
        #expect(settings.paletteSet == .classicDMG)
    }

    @Test func paletteSetExposesBuiltInIDAndDisplayName() {
        let expectedNames: [(GameBoyPaletteSet, String, String)] = [
            (.dmgMeetsColor, "dmgMeetsColor", "BERRY"),
            (.classicDMG,    "classicDMG",    "STONE"),
            (.atomicRed,     "atomicRed",     "ATOMIC"),
            (.oceanBlue,     "oceanBlue",     "OCEAN"),
            (.mint,          "mint",          "MINT"),
            (.pink,          "pink",          "PINK"),
            (.yellow,        "yellow",        "YELLOW"),
            (.orange,        "orange",        "ORANGE"),
            (.purple,        "purple",        "PURPLE"),
            (.black,         "black",         "BLACK")
        ]
        for (set, id, name) in expectedNames {
            #expect(set.builtInID  == id,   "id mismatch for \(name)")
            #expect(set.displayName == name, "name mismatch for \(id)")
        }
    }

    @Test func builtInLookupRoundTripsByID() {
        for entry in GameBoyPaletteSet.builtIns {
            #expect(GameBoyPaletteSet.builtIn(id: entry.id) == entry.set,
                    "lookup failed for \(entry.id)")
        }
        #expect(GameBoyPaletteSet.builtIn(id: "nonsense") == nil)
    }

    @Test func tenBuiltInColors() {
        #expect(GameBoyPaletteSet.builtIns.count == 10)
    }

    @Test func themePersistsRoundTrip() {
        let suite = "gbk.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Quick smoke: GameBoyTheme rawValues are stable strings.
        #expect(GameBoyTheme.light.rawValue == "light")
        #expect(GameBoyTheme.dark.rawValue == "dark")
        #expect(GameBoyTheme.system.rawValue == "system")
        defaults.removePersistentDomain(forName: suite)
    }
}
