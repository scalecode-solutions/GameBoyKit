import SwiftUI
import GameBoyKit

/// The "system settings" overlay. Rendered inside the LCD when the
/// user opens it from the cartridge shelf (via the MENU button).
/// Driven by D-pad up/down to move the cursor, ◁▷ to change a value
/// inline, A to enter sub-screens, B or MENU to exit.
internal struct DeviceMenu: View {

    let input: GameBoyInput
    let palette: GameBoyPalette
    let onClose: () -> Void

    @Environment(\.deviceSettings) private var settings

    @State private var selectedIndex: Int = 0
    @State private var subScreen: SubScreen? = nil

    enum SubScreen: Equatable {
        case about
        case inputTest
    }

    private enum Item: Int, CaseIterable {
        case theme, haptics, about, inputTest

        var title: String {
            switch self {
            case .theme:     return "THEME"
            case .haptics:   return "HAPTICS"
            case .about:     return "ABOUT"
            case .inputTest: return "INPUT TEST"
            }
        }
    }

    var body: some View {
        Group {
            switch subScreen {
            case .none:      mainList
            case .about:     AboutSubScreen(palette: palette,
                                            input: input,
                                            onExit: { subScreen = nil })
            case .inputTest: InputTestSubScreen(palette: palette,
                                                input: input,
                                                onExit: { subScreen = nil })
            }
        }
    }

    // MARK: - Main list

    @ViewBuilder
    private var mainList: some View {
        PixelCanvas { ctx, scale in
            // Dim layer under the menu
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade3.opacity(0.65), scale: scale)
            // Menu panel
            ctx.fillPixel(x: 16, y: 12, width: 224, height: 120,
                          color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: 16, y: 12,  width: 224, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 16, y: 131, width: 224, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 16, y: 12, width: 1, height: 120, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 239, y: 12, width: 1, height: 120, color: palette.lcdShade3, scale: scale)

            // Title bar
            ctx.fillPixel(x: 16, y: 12, width: 224, height: 16,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("DEVICE")
                    .font(.system(size: 11 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 128 * scale.width, y: 20 * scale.height),
                anchor: .center
            )

            // Items
            for (i, item) in Item.allCases.enumerated() {
                let yTop = 36 + i * 18
                let isSelected = i == selectedIndex
                if isSelected {
                    ctx.fillPixel(x: 22, y: yTop - 2, width: 212, height: 16,
                                  color: palette.lcdShade2, scale: scale)
                    // ▶ pointer
                    ctx.fillPixel(x: 26, y: yTop + 2, width: 2, height: 6,
                                  color: palette.lcdShade0, scale: scale)
                    ctx.fillPixel(x: 28, y: yTop + 4, width: 1, height: 2,
                                  color: palette.lcdShade0, scale: scale)
                }
                // Left: item title
                ctx.draw(
                    Text(item.title)
                        .font(.system(size: 10 * scale.height,
                                      weight: .heavy,
                                      design: .monospaced))
                        .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade3),
                    at: CGPoint(x: 34 * scale.width, y: CGFloat(yTop + 5) * scale.height),
                    anchor: .leading
                )
                // Right: current value
                if let valueText = valueLabel(for: item) {
                    ctx.draw(
                        Text(valueText)
                            .font(.system(size: 10 * scale.height,
                                          weight: .heavy,
                                          design: .monospaced))
                            .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade2),
                        at: CGPoint(x: 228 * scale.width, y: CGFloat(yTop + 5) * scale.height),
                        anchor: .trailing
                    )
                }
            }

            // Controls hint
            ctx.draw(
                Text("◁▷ EDIT   A: ENTER   B/MENU: CLOSE")
                    .font(.system(size: 7 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 125 * scale.height),
                anchor: .center
            )
        }
        .onChange(of: input.dpad) { _, dir in
            guard let dir else { return }
            if dir.isUp   { selectedIndex = (selectedIndex - 1 + Item.allCases.count) % Item.allCases.count }
            if dir.isDown { selectedIndex = (selectedIndex + 1) % Item.allCases.count }
            if dir.isLeft  { adjustSelection(by: -1) }
            if dir.isRight { adjustSelection(by: +1) }
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard pressed else { return }
            activateSelection()
        }
        .onChange(of: input.bPressed)    { _, pressed in if pressed { onClose() } }
        .onChange(of: input.menuPressed) { _, pressed in if pressed { onClose() } }
    }

    // MARK: - Item logic

    private func valueLabel(for item: Item) -> String? {
        switch item {
        case .theme:     return settings.paletteSet.displayName
        case .haptics:   return settings.hapticsEnabled ? "ON" : "OFF"
        case .about,
             .inputTest: return "─►"
        }
    }

    /// Inline ◁▷ adjustment for toggle/picker items.
    private func adjustSelection(by delta: Int) {
        guard let item = Item(rawValue: selectedIndex) else { return }
        switch item {
        case .theme:
            let builtIns = GameBoyPaletteSet.builtIns
            guard !builtIns.isEmpty else { return }
            let currentIdx = builtIns.firstIndex(where: { $0.set == settings.paletteSet }) ?? 0
            let next = (currentIdx + delta + builtIns.count) % builtIns.count
            settings.paletteSet = builtIns[next].set
        case .haptics:
            settings.hapticsEnabled.toggle()
        case .about, .inputTest:
            break
        }
    }

    /// A-button behavior — toggles for boolean items, opens sub-screen
    /// for navigable items.
    private func activateSelection() {
        guard let item = Item(rawValue: selectedIndex) else { return }
        switch item {
        case .theme:     adjustSelection(by: +1)        // A also cycles theme
        case .haptics:   settings.hapticsEnabled.toggle()
        case .about:     subScreen = .about
        case .inputTest: subScreen = .inputTest
        }
    }
}

// MARK: - About sub-screen

private struct AboutSubScreen: View {
    let palette: GameBoyPalette
    let input: GameBoyInput
    let onExit: () -> Void

    var body: some View {
        PixelCanvas { ctx, scale in
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 16,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("ABOUT")
                    .font(.system(size: 11 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 128 * scale.width, y: 8 * scale.height),
                anchor: .center
            )
            ctx.draw(
                Text("GAMEBOYKIT")
                    .font(.system(size: 16 * scale.height,
                                  weight: .black,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 44 * scale.height),
                anchor: .center
            )
            ctx.draw(
                Text("v0.4 · CONSOLEKIT")
                    .font(.system(size: 9 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 62 * scale.height),
                anchor: .center
            )
            ctx.draw(
                Text("by travis ®")
                    .font(.system(size: 9 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 90 * scale.height),
                anchor: .center
            )
            ctx.draw(
                Text("B/MENU: BACK")
                    .font(.system(size: 8 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 124 * scale.height),
                anchor: .center
            )
        }
        .onChange(of: input.bPressed)    { _, pressed in if pressed { onExit() } }
        .onChange(of: input.menuPressed) { _, pressed in if pressed { onExit() } }
        .onChange(of: input.aPressed)    { _, pressed in if pressed { onExit() } }
    }
}

// MARK: - Input test sub-screen

private struct InputTestSubScreen: View {
    let palette: GameBoyPalette
    let input: GameBoyInput
    let onExit: () -> Void

    var body: some View {
        PixelCanvas { ctx, scale in
            // Background
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade0, scale: scale)
            // Header
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 14,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("INPUT TEST")
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 128 * scale.width, y: 7 * scale.height),
                anchor: .center
            )

            // D-pad cross (left side)
            drawDpad(into: &ctx, scale: scale)
            // Action buttons (right side)
            drawActionButtons(into: &ctx, scale: scale)
            // System buttons + MENU (bottom)
            drawSystemButtons(into: &ctx, scale: scale)

            // Footer hint
            ctx.draw(
                Text("B/MENU: BACK")
                    .font(.system(size: 7 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 138 * scale.height),
                anchor: .center
            )
        }
        .onChange(of: input.bPressed)    { _, pressed in if pressed { onExit() } }
        .onChange(of: input.menuPressed) { _, pressed in if pressed { onExit() } }
    }

    private func drawDpad(into ctx: inout GraphicsContext, scale: CGSize) {
        let cx = 60, cy = 70
        let armLong: Int = 16
        let armShort: Int = 10
        // Vertical arm (up/down)
        ctx.fillPixel(x: cx - armShort/2, y: cy - armLong,
                      width: armShort, height: armLong * 2,
                      color: palette.lcdShade2, scale: scale)
        // Horizontal arm (left/right)
        ctx.fillPixel(x: cx - armLong, y: cy - armShort/2,
                      width: armLong * 2, height: armShort,
                      color: palette.lcdShade2, scale: scale)

        // Highlights when pressed
        if input.dpad?.isUp ?? false {
            ctx.fillPixel(x: cx - armShort/2 + 1, y: cy - armLong + 1,
                          width: armShort - 2, height: armLong - 2,
                          color: palette.lcdShade3, scale: scale)
        }
        if input.dpad?.isDown ?? false {
            ctx.fillPixel(x: cx - armShort/2 + 1, y: cy + 1,
                          width: armShort - 2, height: armLong - 2,
                          color: palette.lcdShade3, scale: scale)
        }
        if input.dpad?.isLeft ?? false {
            ctx.fillPixel(x: cx - armLong + 1, y: cy - armShort/2 + 1,
                          width: armLong - 2, height: armShort - 2,
                          color: palette.lcdShade3, scale: scale)
        }
        if input.dpad?.isRight ?? false {
            ctx.fillPixel(x: cx + 1, y: cy - armShort/2 + 1,
                          width: armLong - 2, height: armShort - 2,
                          color: palette.lcdShade3, scale: scale)
        }
    }

    private func drawActionButtons(into ctx: inout GraphicsContext, scale: CGSize) {
        // B (left)
        drawButton(into: &ctx, scale: scale,
                   cx: 170, cy: 76, radius: 11,
                   label: "B", pressed: input.bPressed)
        // A (right)
        drawButton(into: &ctx, scale: scale,
                   cx: 210, cy: 60, radius: 11,
                   label: "A", pressed: input.aPressed)
    }

    private func drawSystemButtons(into ctx: inout GraphicsContext, scale: CGSize) {
        // SELECT pill
        drawPill(into: &ctx, scale: scale,
                 x: 30, y: 110, w: 50, h: 12,
                 label: "SEL", pressed: input.selectPressed)
        // START pill
        drawPill(into: &ctx, scale: scale,
                 x: 100, y: 110, w: 50, h: 12,
                 label: "STA", pressed: input.startPressed)
        // MENU pill
        drawPill(into: &ctx, scale: scale,
                 x: 176, y: 110, w: 50, h: 12,
                 label: "MEN", pressed: input.menuPressed)
    }

    private func drawButton(
        into ctx: inout GraphicsContext, scale: CGSize,
        cx: Int, cy: Int, radius: Int, label: String, pressed: Bool
    ) {
        let r = radius
        ctx.fillPixel(x: cx - r, y: cy - r, width: r * 2, height: r * 2,
                      color: pressed ? palette.lcdShade3 : palette.lcdShade2, scale: scale)
        ctx.draw(
            Text(label)
                .font(.system(size: 10 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(pressed ? palette.lcdShade0 : palette.lcdShade3),
            at: CGPoint(x: CGFloat(cx) * scale.width,
                        y: CGFloat(cy) * scale.height),
            anchor: .center
        )
    }

    private func drawPill(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, w: Int, h: Int, label: String, pressed: Bool
    ) {
        ctx.fillPixel(x: x, y: y, width: w, height: h,
                      color: pressed ? palette.lcdShade3 : palette.lcdShade2, scale: scale)
        ctx.draw(
            Text(label)
                .font(.system(size: 8 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(pressed ? palette.lcdShade0 : palette.lcdShade3),
            at: CGPoint(x: CGFloat(x + w/2) * scale.width,
                        y: CGFloat(y + h/2) * scale.height),
            anchor: .center
        )
    }
}
