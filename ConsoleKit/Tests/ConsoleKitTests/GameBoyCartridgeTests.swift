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

    @Test func pixelGridIs256x144_andTrueSixteenNine() {
        #expect(PixelGrid.width == 256)
        #expect(PixelGrid.height == 144)
        // 16:9 (256 × 9 == 144 × 16)
        #expect(PixelGrid.width * 9 == PixelGrid.height * 16)
        // Both dimensions divisible by 8 → tidy 32×18 grid for 8px cells
        #expect(PixelGrid.width % 8 == 0)
        #expect(PixelGrid.height % 8 == 0)
    }
}
