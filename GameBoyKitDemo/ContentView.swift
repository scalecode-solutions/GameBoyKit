import SwiftUI
import GameBoyKit
import ConsoleKit
import CartridgeKit

struct ContentView: View {
    @State private var isPoweredOn: Bool = true

    var body: some View {
        // GameBoyView is the entire face now — give it the whole screen
        // with no wrapping padded containers, no backdrop, no spacers.
        // It paints its own face gradient edge-to-edge.
        GameBoyView(
            screen: { input in
                CartridgeShelf(
                    input: input,
                    cartridges: [
                        .snake,
                        .questKid,
                        .lander,
                        .hopper
                    ]
                )
            },
            headline: { Text("mvBOY") },
            subtitle: { Text("DOT MATRIX • TAP & DRAG") },
            brand:    { Text("MV®") },
            aLabel: "A",
            bLabel: "B",
            startLabel: "START",
            selectLabel: "SELECT",
            powerOn: $isPoweredOn,
            palette: .dmgMeetsColor
            // theme defaults to .system — follows colorScheme automatically
        )
    }
}

#Preview("Light") {
    ContentView().preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView().preferredColorScheme(.dark)
}
