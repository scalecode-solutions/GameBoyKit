import SwiftUI
import GameBoyKit

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
    @State private var showMenuConfirm: Bool = false
    @State private var showDeviceMenu: Bool = false
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
                ZStack {
                    menuView
                    if showDeviceMenu {
                        DeviceMenu(
                            input: input,
                            palette: palette,
                            onClose: { showDeviceMenu = false }
                        )
                    }
                }
                .onChange(of: input.menuPressed) { _, pressed in
                    guard powerOn, pressed else { return }
                    showDeviceMenu.toggle()
                }
            case .playing(let cart):
                ZStack {
                    // While the confirmation dialog is open we override
                    // `gameBoyPowerOn` inside the cartridge subtree only.
                    // Cartridges already pause their tick + ignore input
                    // when they see powerOn = false, so this freezes the
                    // game without touching the LCD's visual dimming
                    // (which is driven by the binding at the GameBoyView
                    // level, not the env value).
                    cart.make(input)
                        .environment(\.gameBoyPowerOn, powerOn && !showMenuConfirm)

                    if showMenuConfirm {
                        MenuConfirmation(
                            input: input,
                            palette: palette,
                            onConfirm: {
                                showMenuConfirm = false
                                phase = .menu
                            },
                            onCancel: {
                                showMenuConfirm = false
                            }
                        )
                    }
                }
                .onChange(of: input.menuPressed) { _, pressed in
                    guard powerOn, pressed else { return }
                    // Toggle dialog visibility on each MENU press.
                    showMenuConfirm.toggle()
                }
            }
        }
    }

    // MARK: - Boot splash

    private var bootSplash: some View {
        PixelCanvas { ctx, scale in
            // Solid background (the LCD already paints lcdBackground;
            // we draw shade0 over it to commit to our 4-shade palette).
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade0, scale: scale)

            // Title card borders (top + bottom strips)
            ctx.fillPixel(x: 0, y: 0,   width: 256, height: 8, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 0, y: 136, width: 256, height: 8, color: palette.lcdShade3, scale: scale)

            // "GAMEBOYKIT" centered
            ctx.draw(
                Text("GAMEBOYKIT")
                    .font(.system(size: 18 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 64 * scale.height),
                anchor: .center
            )

            // Subtitle
            ctx.draw(
                Text("INSERT CARTRIDGE")
                    .font(.system(size: 9 * scale.height,
                                  weight: .bold,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 88 * scale.height),
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
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade0, scale: scale)

            // Title bar
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 16,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("CARTRIDGES")
                    .font(.system(size: 11 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 128 * scale.width, y: 8 * scale.height),
                anchor: .center
            )

            // List
            let rowHeight = 16
            let listStartY = 26
            for (i, cart) in cartridges.enumerated() {
                let yTop = listStartY + i * rowHeight
                let isSelected = i == selectedIndex
                if isSelected {
                    ctx.fillPixel(x: 8, y: yTop - 2, width: 240, height: rowHeight - 2,
                                  color: palette.lcdShade2, scale: scale)
                    // Triangle pointer (▶)
                    ctx.fillPixel(x: 14, y: yTop + 2, width: 2, height: 6, color: palette.lcdShade0, scale: scale)
                    ctx.fillPixel(x: 16, y: yTop + 4, width: 1, height: 2, color: palette.lcdShade0, scale: scale)
                }
                ctx.draw(
                    Text(cart.title)
                        .font(.system(size: 10 * scale.height,
                                      weight: .heavy,
                                      design: .monospaced))
                        .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade3),
                    at: CGPoint(x: 24 * scale.width, y: CGFloat(yTop + 5) * scale.height),
                    anchor: .leading
                )
            }

            // Blurb footer for selected cartridge
            if cartridges.indices.contains(selectedIndex) {
                let cart = cartridges[selectedIndex]
                if !cart.blurb.isEmpty {
                    ctx.fillPixel(x: 0, y: 128, width: 256, height: 16,
                                  color: palette.lcdShade1, scale: scale)
                    ctx.draw(
                        Text(cart.blurb)
                            .font(.system(size: 9 * scale.height,
                                          weight: .semibold,
                                          design: .monospaced))
                            .foregroundColor(palette.lcdShade3),
                        at: CGPoint(x: 128 * scale.width, y: 136 * scale.height),
                        anchor: .center
                    )
                }
            }
        }
        .onChange(of: input.dpad) { _, newValue in
            guard powerOn, !showDeviceMenu, !cartridges.isEmpty else { return }
            if newValue?.isUp == true {
                selectedIndex = (selectedIndex - 1 + cartridges.count) % cartridges.count
            } else if newValue?.isDown == true {
                selectedIndex = (selectedIndex + 1) % cartridges.count
            }
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard powerOn, !showDeviceMenu, pressed,
                  cartridges.indices.contains(selectedIndex) else { return }
            phase = .playing(cartridges[selectedIndex])
        }
    }
}
