import Testing
import Foundation
@testable import ConsoleKit

struct CartridgeScoresTests {

    /// Each test gets a fresh isolated UserDefaults so we don't
    /// pollute the running app's real preferences.
    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "CartridgeScoresTests.\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func bestStartsAtZero() {
        let d = freshDefaults()
        #expect(CartridgeScores.best(cartridge: "snake", mode: "classic", in: d) == 0)
    }

    @Test func recordIfBetterStoresAndReturnsTrue() {
        let d = freshDefaults()
        let updated = CartridgeScores.recordIfBetter(120, cartridge: "snake", mode: "classic", in: d)
        #expect(updated == true)
        #expect(CartridgeScores.best(cartridge: "snake", mode: "classic", in: d) == 120)
    }

    @Test func recordIfBetterIgnoresLowerScores() {
        let d = freshDefaults()
        CartridgeScores.recordIfBetter(500, cartridge: "lander", mode: "classic", in: d)
        let updated = CartridgeScores.recordIfBetter(300, cartridge: "lander", mode: "classic", in: d)
        #expect(updated == false)
        #expect(CartridgeScores.best(cartridge: "lander", mode: "classic", in: d) == 500)
    }

    @Test func recordsArePerCartridgeAndMode() {
        let d = freshDefaults()
        CartridgeScores.recordIfBetter(100, cartridge: "lander", mode: "classic", in: d)
        CartridgeScores.recordIfBetter(200, cartridge: "lander", mode: "pendulum", in: d)
        CartridgeScores.recordIfBetter(300, cartridge: "hopper", mode: "classic", in: d)
        #expect(CartridgeScores.best(cartridge: "lander", mode: "classic",  in: d) == 100)
        #expect(CartridgeScores.best(cartridge: "lander", mode: "pendulum", in: d) == 200)
        #expect(CartridgeScores.best(cartridge: "hopper", mode: "classic",  in: d) == 300)
    }

    @Test func keysAreCaseNormalized() {
        let d = freshDefaults()
        CartridgeScores.recordIfBetter(50, cartridge: "Lander", mode: "Classic", in: d)
        // Same logical key regardless of case.
        #expect(CartridgeScores.best(cartridge: "lander", mode: "classic", in: d) == 50)
        #expect(CartridgeScores.best(cartridge: "LANDER", mode: "CLASSIC", in: d) == 50)
    }

    @Test func resetClearsAllScores() {
        let d = freshDefaults()
        CartridgeScores.recordIfBetter(100, cartridge: "lander", mode: "classic", in: d)
        CartridgeScores.recordIfBetter(200, cartridge: "hopper", mode: "endless", in: d)
        CartridgeScores.reset(in: d)
        #expect(CartridgeScores.best(cartridge: "lander", mode: "classic", in: d) == 0)
        #expect(CartridgeScores.best(cartridge: "hopper", mode: "endless", in: d) == 0)
    }

    @Test func resetIgnoresUnrelatedDefaults() {
        let d = freshDefaults()
        d.set("unrelated value", forKey: "some.other.app.setting")
        CartridgeScores.recordIfBetter(100, cartridge: "lander", mode: "classic", in: d)
        CartridgeScores.reset(in: d)
        #expect(d.string(forKey: "some.other.app.setting") == "unrelated value")
    }
}
