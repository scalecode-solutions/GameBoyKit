import SwiftUI

/// The view that lives inside `GameBoyView`'s screen slot when you
/// want a multi-game console experience. Manages three phases:
///
/// - **boot**: a brief "GAMEBOYKIT" splash (~1.2s)
/// - **menu**: vertical list of cartridges; D-pad navigates, A loads
/// - **playing**: renders the selected cartridge's view; Start returns to menu
///
/// Drop into a `GameBoyView`:
/// ```swift
/// GameBoyView(
///     screen: { input in
///         CartridgeShelf(input: input, cartridges: [.snake])
///     }
/// )
/// ```
public struct CartridgeShelf: View {

    enum Phase: Equatable {
        case boot
        case menu
        case playing(GameBoyCartridge)
    }

    public let cartridges: [GameBoyCartridge]
    public let input: GameBoyInput

    @State private var phase: Phase = .boot
    @State private var selectedIndex: Int = 0
    @Environment(\.gameBoyPalette) private var palette
    @Environment(\.gameBoyPowerOn) private var powerOn

    public init(input: GameBoyInput, cartridges: [GameBoyCartridge]) {
        self.input = input
        self.cartridges = cartridges
    }

    public var body: some View {
        Group {
            switch phase {
            case .boot:
                bootSplash
            case .menu:
                menuView
            case .playing(let cart):
                cart.make(input)
                    .onChange(of: input.startPressed) { _, pressed in
                        guard powerOn, pressed else { return }
                        phase = .menu
                    }
            }
        }
    }

    // MARK: - Boot splash

    private var bootSplash: some View {
        PixelCanvas { ctx, scale in
            // Solid background (the LCD already paints lcdBackground;
            // we draw shade0 over it to commit to our 4-shade palette).
            ctx.fillPixel(x: 0, y: 0, width: 160, height: 120,
                          color: palette.lcdShade0, scale: scale)

            // Title card border
            ctx.fillPixel(x: 0, y: 0, width: 160, height: 8, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 0, y: 112, width: 160, height: 8, color: palette.lcdShade3, scale: scale)

            // "GAMEBOYKIT" centered
            ctx.draw(
                Text("GAMEBOYKIT")
                    .font(.system(size: 16 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 80 * scale.width, y: 56 * scale.height),
                anchor: .center
            )

            // Subtitle
            ctx.draw(
                Text("INSERT CARTRIDGE")
                    .font(.system(size: 8 * scale.height,
                                  weight: .bold,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 80 * scale.width, y: 78 * scale.height),
                anchor: .center
            )
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.easeInOut(duration: 0.2)) { phase = .menu }
        }
    }

    // MARK: - Menu

    private var menuView: some View {
        PixelCanvas { ctx, scale in
            // Background
            ctx.fillPixel(x: 0, y: 0, width: 160, height: 120,
                          color: palette.lcdShade0, scale: scale)

            // Title bar
            ctx.fillPixel(x: 0, y: 0, width: 160, height: 14,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("CARTRIDGES")
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 80 * scale.width, y: 7 * scale.height),
                anchor: .center
            )

            // List
            let rowHeight = 14
            for (i, cart) in cartridges.enumerated() {
                let yTop = 20 + i * rowHeight
                let isSelected = i == selectedIndex
                if isSelected {
                    ctx.fillPixel(x: 4, y: yTop - 2, width: 152, height: rowHeight - 2,
                                  color: palette.lcdShade2, scale: scale)
                    // Triangle pointer (▶)
                    ctx.fillPixel(x: 8, y: yTop + 2, width: 2, height: 4, color: palette.lcdShade0, scale: scale)
                    ctx.fillPixel(x: 10, y: yTop + 3, width: 1, height: 2, color: palette.lcdShade0, scale: scale)
                }
                ctx.draw(
                    Text(cart.title)
                        .font(.system(size: 9 * scale.height,
                                      weight: .heavy,
                                      design: .monospaced))
                        .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade3),
                    at: CGPoint(x: 16 * scale.width, y: CGFloat(yTop + 4) * scale.height),
                    anchor: .leading
                )
            }

            // Blurb footer for selected cartridge
            if cartridges.indices.contains(selectedIndex) {
                let cart = cartridges[selectedIndex]
                if !cart.blurb.isEmpty {
                    ctx.fillPixel(x: 0, y: 106, width: 160, height: 14,
                                  color: palette.lcdShade1, scale: scale)
                    ctx.draw(
                        Text(cart.blurb)
                            .font(.system(size: 8 * scale.height,
                                          weight: .semibold,
                                          design: .monospaced))
                            .foregroundColor(palette.lcdShade3),
                        at: CGPoint(x: 80 * scale.width, y: 113 * scale.height),
                        anchor: .center
                    )
                }
            }
        }
        .onChange(of: input.dpad) { _, newValue in
            guard powerOn, !cartridges.isEmpty else { return }
            if newValue?.isUp == true {
                selectedIndex = (selectedIndex - 1 + cartridges.count) % cartridges.count
            } else if newValue?.isDown == true {
                selectedIndex = (selectedIndex + 1) % cartridges.count
            }
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard powerOn, pressed, cartridges.indices.contains(selectedIndex) else { return }
            phase = .playing(cartridges[selectedIndex])
        }
    }
}
