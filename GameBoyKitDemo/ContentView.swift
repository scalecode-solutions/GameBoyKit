import SwiftUI
import GameBoyKit
import ConsoleKit
import CartridgeKit

struct ContentView: View {
    @State private var isPoweredOn: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Adaptive backdrop that tracks the system color scheme.
            backdrop.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                GameBoyView(
                    screen: { input in
                        CartridgeShelf(
                            input: input,
                            cartridges: [
                                .snake,
                                .questKid,
                                // Placeholder showing the menu has scale.
                                .comingSoon(id: "lander", title: "LANDER")
                            ]
                        )
                    },
                    headline: { Text("CLINGY BOY") },
                    subtitle: { Text("DOT MATRIX • TAP & DRAG") },
                    brand:    { Text("travis ®") },
                    aLabel: "A",
                    bLabel: "B",
                    startLabel: "START",
                    selectLabel: "SELECT",
                    powerOn: $isPoweredOn,
                    palette: .dmgMeetsColor
                    // theme defaults to .system — follows colorScheme automatically
                )
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.12, blue: 0.18),
                        Color(red: 0.05, green: 0.04, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.90, blue: 0.95),
                        Color(red: 0.82, green: 0.80, blue: 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

#Preview("Light") {
    ContentView().preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView().preferredColorScheme(.dark)
}
