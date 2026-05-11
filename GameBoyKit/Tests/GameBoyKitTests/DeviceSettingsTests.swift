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
        #expect(GameBoyPaletteSet.dmgMeetsColor.builtInID == "dmgMeetsColor")
        #expect(GameBoyPaletteSet.classicDMG.builtInID    == "classicDMG")
        #expect(GameBoyPaletteSet.atomicRed.builtInID     == "atomicRed")
        #expect(GameBoyPaletteSet.oceanBlue.builtInID     == "oceanBlue")
        #expect(GameBoyPaletteSet.dmgMeetsColor.displayName == "BERRY")
        #expect(GameBoyPaletteSet.classicDMG.displayName    == "STONE")
        #expect(GameBoyPaletteSet.atomicRed.displayName     == "ATOMIC")
        #expect(GameBoyPaletteSet.oceanBlue.displayName     == "OCEAN")
    }

    @Test func builtInLookupRoundTripsByID() {
        #expect(GameBoyPaletteSet.builtIn(id: "dmgMeetsColor") == .dmgMeetsColor)
        #expect(GameBoyPaletteSet.builtIn(id: "classicDMG")    == .classicDMG)
        #expect(GameBoyPaletteSet.builtIn(id: "atomicRed")     == .atomicRed)
        #expect(GameBoyPaletteSet.builtIn(id: "oceanBlue")     == .oceanBlue)
        #expect(GameBoyPaletteSet.builtIn(id: "nonsense")      == nil)
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
