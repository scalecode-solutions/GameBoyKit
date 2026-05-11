import Testing
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
        #expect(GameBoyPaletteSet.dmgMeetsColor.displayName == "DMG × COLOR")
        #expect(GameBoyPaletteSet.classicDMG.displayName    == "CLASSIC DMG")
    }

    @Test func builtInLookupRoundTripsByID() {
        #expect(GameBoyPaletteSet.builtIn(id: "dmgMeetsColor") == .dmgMeetsColor)
        #expect(GameBoyPaletteSet.builtIn(id: "classicDMG")    == .classicDMG)
        #expect(GameBoyPaletteSet.builtIn(id: "nonsense")      == nil)
    }
}
