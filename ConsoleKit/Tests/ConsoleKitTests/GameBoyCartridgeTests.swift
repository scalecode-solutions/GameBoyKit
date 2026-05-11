import Testing
import SwiftUI
import GameBoyKit
@testable import ConsoleKit

@MainActor
struct GameBoyCartridgeTests {

    @Test func cartridgeBuildsViewWithProvidedInput() {
        let input = GameBoyInput()
        var captured: ObjectIdentifier? = nil
        let cart = GameBoyCartridge(
            id: "test",
            title: "TEST",
            blurb: "for tests",
            make: { i in
                captured = ObjectIdentifier(i)
                return Color.clear
            }
        )
        _ = cart.make(input)
        #expect(captured == ObjectIdentifier(input))
        #expect(cart.id == "test")
        #expect(cart.title == "TEST")
        #expect(cart.blurb == "for tests")
    }

    @Test func cartridgesEqualByID() {
        let a = GameBoyCartridge(id: "x", title: "X", make: { _ in Color.clear })
        let b = GameBoyCartridge(id: "x", title: "Y", make: { _ in Color.red   })
        let c = GameBoyCartridge(id: "z", title: "X", make: { _ in Color.clear })
        #expect(a == b)
        #expect(a != c)
    }

    @Test func pixelGridIs160x120() {
        #expect(PixelGrid.width == 160)
        #expect(PixelGrid.height == 120)
        // 4:3 aspect (160/120 = 4/3)
        #expect(PixelGrid.width * 3 == PixelGrid.height * 4)
    }
}
