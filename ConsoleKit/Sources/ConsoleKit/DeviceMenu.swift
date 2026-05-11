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
    /// Optional — when provided, an extra "RETURN TO LIBRARY" item is
    /// shown at the bottom of the menu. CartridgeShelf supplies this
    /// only when a cartridge is currently playing, so the option is
    /// hidden on the shelf itself (where it would be a no-op).
    let onReturnToLibrary: (() -> Void)?

    @Environment(\.deviceSettings) private var settings

    @State private var selectedIndex: Int = 0
    @State private var subScreen: SubScreen? = nil

    init(
        input: GameBoyInput,
        palette: GameBoyPalette,
        onClose: @escaping () -> Void,
        onReturnToLibrary: (() -> Void)? = nil
    ) {
        self.input = input
        self.palette = palette
        self.onClose = onClose
        self.onReturnToLibrary = onReturnToLibrary
    }

    enum SubScreen: Equatable {
        case about
        case inputTest
    }

    private enum Item: Int, CaseIterable {
        case color, theme, haptics, about, inputTest, returnToLibrary

        var title: String {
            switch self {
            case .color:           return "COLOR"
            case .theme:           return "THEME"
            case .haptics:         return "HAPTICS"
            case .about:           return "ABOUT"
            case .inputTest:       return "INPUT TEST"
            case .returnToLibrary: return "EXIT TO LIBRARY"
            }
        }
    }

    /// The actual items shown right now — hides RETURN TO LIBRARY when
    /// no onReturnToLibrary handler is wired up.
    private var visibleItems: [Item] {
        Item.allCases.filter { item in
            item == .returnToLibrary ? onReturnToLibrary != nil : true
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
            // Full-LCD opaque background so nothing underneath bleeds
            // through (was previously a translucent panel with strips
            // of cartridge-shelf content visible at the top and bottom).
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade0, scale: scale)

            // Title bar — full width, full top of LCD.
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 14,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("DEVICE")
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 128 * scale.width, y: 7 * scale.height),
                anchor: .center
            )

            // Items — tighter row spacing so all 6 fit cleanly above the hint.
            let items = visibleItems
            let rowHeight = 13
            let listStartY = 22
            for (i, item) in items.enumerated() {
                let yTop = listStartY + i * rowHeight
                let isSelected = i == selectedIndex
                if isSelected {
                    ctx.fillPixel(x: 6, y: yTop - 1, width: 244, height: rowHeight - 1,
                                  color: palette.lcdShade2, scale: scale)
                    // ▶ pointer
                    ctx.fillPixel(x: 10, y: yTop + 2, width: 2, height: 5,
                                  color: palette.lcdShade0, scale: scale)
                    ctx.fillPixel(x: 12, y: yTop + 3, width: 1, height: 3,
                                  color: palette.lcdShade0, scale: scale)
                }
                // Left: item title
                ctx.draw(
                    Text(item.title)
                        .font(.system(size: 10 * scale.height,
                                      weight: .heavy,
                                      design: .monospaced))
                        .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade3),
                    at: CGPoint(x: 20 * scale.width, y: CGFloat(yTop + 5) * scale.height),
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
                        at: CGPoint(x: 244 * scale.width, y: CGFloat(yTop + 5) * scale.height),
                        anchor: .trailing
                    )
                }
            }

            // Bottom hint strip
            ctx.fillPixel(x: 0, y: 130, width: 256, height: 14,
                          color: palette.lcdShade3, scale: scale)
            ctx.draw(
                Text("◁▷ EDIT   A: ENTER   B/MENU: CLOSE")
                    .font(.system(size: 7 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade0),
                at: CGPoint(x: 128 * scale.width, y: 137 * scale.height),
                anchor: .center
            )
        }
        .onChange(of: input.dpad) { _, dir in
            guard let dir else { return }
            let count = visibleItems.count
            if dir.isUp   { selectedIndex = (selectedIndex - 1 + count) % count }
            if dir.isDown { selectedIndex = (selectedIndex + 1) % count }
            if dir.isLeft  { adjustSelection(by: -1) }
            if dir.isRight { adjustSelection(by: +1) }
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard pressed else { return }
            activateSelection()
        }
        .onChange(of: input.bPressed) { _, pressed in if pressed { onClose() } }
        // NB: MENU close is handled by CartridgeShelf (which owns the
        // toggle state). If we also listened here, both handlers would
        // fire on the same press and cancel each other out.
    }

    // MARK: - Item logic

    private func valueLabel(for item: Item) -> String? {
        switch item {
        case .color:           return settings.paletteSet.displayName
        case .theme:           return themeDisplayName(settings.theme)
        case .haptics:         return settings.hapticsEnabled ? "ON" : "OFF"
        case .about,
             .inputTest,
             .returnToLibrary: return "─►"
        }
    }

    private func themeDisplayName(_ theme: GameBoyTheme) -> String {
        switch theme {
        case .light:  return "LIGHT"
        case .dark:   return "DARK"
        case .system: return "SYSTEM"
        }
    }

    /// Inline ◁▷ adjustment for toggle/picker items.
    private func adjustSelection(by delta: Int) {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        switch item {
        case .color:
            let builtIns = GameBoyPaletteSet.builtIns
            guard !builtIns.isEmpty else { return }
            let currentIdx = builtIns.firstIndex(where: { $0.set == settings.paletteSet }) ?? 0
            let next = (currentIdx + delta + builtIns.count) % builtIns.count
            settings.paletteSet = builtIns[next].set
        case .theme:
            let order: [GameBoyTheme] = [.system, .light, .dark]
            let currentIdx = order.firstIndex(of: settings.theme) ?? 0
            let next = (currentIdx + delta + order.count) % order.count
            settings.theme = order[next]
        case .haptics:
            settings.hapticsEnabled.toggle()
        case .about, .inputTest, .returnToLibrary:
            break
        }
    }

    /// A-button behavior — toggles for boolean items, opens sub-screen
    /// for navigable items.
    private func activateSelection() {
        let items = visibleItems
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        switch item {
        case .color:           adjustSelection(by: +1)
        case .theme:           adjustSelection(by: +1)
        case .haptics:         settings.hapticsEnabled.toggle()
        case .about:           subScreen = .about
        case .inputTest:       subScreen = .inputTest
        case .returnToLibrary:
            onReturnToLibrary?()
            onClose()
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
