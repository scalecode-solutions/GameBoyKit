import SwiftUI
import GameBoyKit

struct ContentView: View {
    @State private var isPoweredOn: Bool = true
    @State private var theme: GameBoyTheme = .system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Adaptive backdrop that follows whichever theme is in effect.
            backdrop.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                GameBoyView(
                    screen:   { input in BlobGameView(input: input) },
                    headline: { Text("CLINGY BOY") },
                    subtitle: { Text("DOT MATRIX • TAP & DRAG") },
                    brand:    { Text("travis ®") },
                    aLabel: "A",
                    bLabel: "B",
                    startLabel: "START",
                    selectLabel: "SELECT",
                    powerOn: $isPoweredOn,
                    palette: .dmgMeetsColor,
                    theme: theme
                )
                .padding(.horizontal, 20)

                themePicker
                    .padding(.horizontal, 40)

                Toggle("Power", isOn: $isPoweredOn)
                    .toggleStyle(.switch)
                    .tint(.green)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 60)

                Spacer()
            }
        }
    }

    // MARK: - Backdrop

    /// Resolves to a light or dark gradient depending on the user's
    /// theme selection (so the page matches the console).
    private var backdrop: some View {
        let effective: ColorScheme = {
            switch theme {
            case .light:  return .light
            case .dark:   return .dark
            case .system: return colorScheme
            }
        }()

        return Group {
            if effective == .dark {
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

    // MARK: - Theme picker

    private var themePicker: some View {
        Picker("Theme", selection: $theme) {
            Text("Light").tag(GameBoyTheme.light)
            Text("System").tag(GameBoyTheme.system)
            Text("Dark").tag(GameBoyTheme.dark)
        }
        .pickerStyle(.segmented)
    }
}

#Preview("Light") {
    ContentView().preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView().preferredColorScheme(.dark)
}
