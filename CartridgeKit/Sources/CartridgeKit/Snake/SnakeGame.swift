import SwiftUI
import GameBoyKit
import ConsoleKit

/// The Snake gameplay view. Hosts a `SnakeState` model, drives ticks
/// while the model is in `.playing`, and renders title / mode-select /
/// snake-on-LCD / death screens into a `PixelCanvas`.
///
/// Controls:
/// - TITLE       — A: open mode select
/// - MODE SELECT — D-pad: navigate, A: confirm
/// - PLAYING     — D-pad: turn (reversing into yourself is ignored);
///                 A or START: pause
/// - PAUSED      — A or START: resume, B: back to mode select
/// - DEAD        — A: retry, START: back to mode select
public struct SnakeGame: View {

    public let input: GameBoyInput
    @State private var state: SnakeState
    @State private var resetCounter: Int = 0   // bumps when we want to restart the task
    @State private var animTick: Int = 0       // 60Hz counter for title pulses
    @State private var lastDpad: DPadDirection? = nil
    @Environment(\.gameBoyPalette) private var palette
    @Environment(\.gameBoyPowerOn) private var powerOn

    public init(input: GameBoyInput) {
        self.input = input
        _state = State(initialValue: SnakeState())
    }

    public var body: some View {
        PixelCanvas { ctx, scale in
            render(into: &ctx, scale: scale)
        }
        .onChange(of: input.dpad) { _, dir in
            guard powerOn else { return }
            handleDpad(dir)
            lastDpad = dir
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard powerOn, pressed else { return }
            handleAPress()
        }
        .onChange(of: input.startPressed) { _, pressed in
            guard powerOn, pressed else { return }
            handleStartPress()
        }
        .onChange(of: input.bPressed) { _, pressed in
            guard powerOn, pressed else { return }
            handleBPress()
        }
        // Including powerOn in the id cancels the loop when off and
        // restarts it (with a fresh sleep) when on.
        .task(id: "\(resetCounter)-\(powerOn)") {
            guard powerOn else { return }
            await runTickLoop()
        }
        .task(id: "anim-\(powerOn)") {
            guard powerOn else { return }
            await runAnimLoop()
        }
    }

    // MARK: - Input

    private func handleDpad(_ dir: DPadDirection?) {
        guard let dir else { return }
        switch state.phase {
        case .modeSelect:
            // Rising-edge — only fire on a fresh press so the cursor
            // doesn't whip on diagonal transitions.
            guard lastDpad == nil else { return }
            if dir.isUp        { state.moveModeSelectCursor(-1) }
            else if dir.isDown { state.moveModeSelectCursor( 1) }
        case .playing:
            if dir.isUp        { state.turn(.up) }
            else if dir.isDown  { state.turn(.down) }
            else if dir.isLeft  { state.turn(.left) }
            else if dir.isRight { state.turn(.right) }
        default:
            break
        }
    }

    private func handleAPress() {
        switch state.phase {
        case .title:
            state.openModeSelect()
        case .modeSelect:
            state.confirmModeSelection()
            resetCounter &+= 1
        case .playing, .paused:
            state.togglePause()
        case .dead:
            state.retryRun()
            resetCounter &+= 1
        }
    }

    private func handleStartPress() {
        switch state.phase {
        case .playing, .paused:
            state.togglePause()
        case .dead:
            state.exitToModeSelect()
        case .title, .modeSelect:
            break
        }
    }

    /// B button — escape hatch from a paused run back to the mode-
    /// select grid. Banner advertises this as "B: MENU".
    private func handleBPress() {
        guard state.phase == .paused else { return }
        state.exitToModeSelect()
    }

    // MARK: - Tick loop

    /// Snake's game tick runs at the variable `state.stepInterval`
    /// (starts at ~6Hz, speeds up). The separate anim loop below
    /// runs at 60Hz so title pulses can animate smoothly while the
    /// game tick is slow / paused.
    private func runTickLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(state.stepInterval))
            if Task.isCancelled { return }
            if state.phase == .playing { state.tick() }
            if state.phase == .dead { return }
        }
    }

    private func runAnimLoop() async {
        let dt: Duration = .milliseconds(16)
        while !Task.isCancelled {
            try? await Task.sleep(for: dt)
            if Task.isCancelled { return }
            animTick &+= 1
            state.bumpAnimationTick()
        }
    }

    // MARK: - Rendering

    private func render(into ctx: inout GraphicsContext, scale: CGSize) {
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                      color: palette.lcdShade0, scale: scale)

        switch state.phase {
        case .title:
            renderTitle(into: &ctx, scale: scale)
        case .modeSelect:
            renderModeSelect(into: &ctx, scale: scale)
        case .playing, .paused, .dead:
            renderGame(into: &ctx, scale: scale)
        }
    }

    // MARK: - Title

    private func renderTitle(into ctx: inout GraphicsContext, scale: CGSize) {
        // Title
        ctx.draw(
            Text("SNAKE")
                .font(.system(size: 30 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 52 * scale.height),
            anchor: .center
        )

        // Hero snake sprite — a coiled little serpent below the title.
        drawTitleSnake(into: &ctx, scale: scale, cx: 128, cy: 92)

        // PRESS A pulse
        if (animTick / 30) % 2 == 0 {
            ctx.draw(
                Text("PRESS A")
                    .font(.system(size: 11 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 128 * scale.height),
                anchor: .center
            )
        }
    }

    /// Coiled snake sprite for the title screen — head + body curling
    /// through a small spiral, drawn with a darker outline.
    private func drawTitleSnake(
        into ctx: inout GraphicsContext, scale: CGSize, cx: Int, cy: Int
    ) {
        // Tail-end segments curving in from the right.
        let segments: [(Int, Int)] = [
            (cx + 14, cy + 4),
            (cx + 10, cy + 4),
            (cx + 6,  cy + 4),
            (cx + 2,  cy + 4),
            (cx - 2,  cy + 4),
            (cx - 6,  cy + 4),
            (cx - 10, cy + 2),
            (cx - 10, cy - 2),
            (cx - 6,  cy - 4),
            (cx - 2,  cy - 4),
            (cx + 2,  cy - 4),
            (cx + 6,  cy - 4),
        ]
        for (x, y) in segments {
            ctx.fillPixel(x: x, y: y, width: 4, height: 4,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: 2, height: 2,
                          color: palette.lcdShade2, scale: scale)
        }
        // Head at the right end of the upper coil.
        let hx = cx + 10, hy = cy - 4
        ctx.fillPixel(x: hx, y: hy, width: 5, height: 4,
                      color: palette.lcdShade3, scale: scale)
        // Eye
        ctx.fillPixel(x: hx + 3, y: hy + 1, width: 1, height: 1,
                      color: palette.lcdShade0, scale: scale)
        // Tongue flick (animated)
        if (animTick / 18) % 3 != 2 {
            ctx.fillPixel(x: hx + 5, y: hy + 2, width: 2, height: 1,
                          color: palette.lcdShade3, scale: scale)
        }
    }

    // MARK: - Mode select

    private func renderModeSelect(into ctx: inout GraphicsContext, scale: CGSize) {
        // Title bar
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 16,
                      color: palette.lcdShade3, scale: scale)
        ctx.draw(
            Text("SELECT MODE")
                .font(.system(size: 11 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade0),
            at: CGPoint(x: 128 * scale.width, y: 8 * scale.height),
            anchor: .center
        )

        // Vertical stack of mode buttons.
        let modes = SnakeState.Mode.allCases
        let rowHeight = 22
        let rowGap = 4
        let rowStartY = 26
        for (i, m) in modes.enumerated() {
            let yTop = rowStartY + i * (rowHeight + rowGap)
            let selected = (i == state.modeSelectCursor)
            ctx.fillPixel(x: 32, y: yTop, width: 192, height: rowHeight,
                          color: selected ? palette.lcdShade2 : palette.lcdShade1,
                          scale: scale)
            ctx.fillPixel(x: 32, y: yTop, width: 192, height: 1,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 32, y: yTop + rowHeight - 1, width: 192, height: 1,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 32, y: yTop, width: 1, height: rowHeight,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 223, y: yTop, width: 1, height: rowHeight,
                          color: palette.lcdShade3, scale: scale)

            ctx.draw(
                Text(m.displayName)
                    .font(.system(size: 12 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width,
                            y: CGFloat(yTop + rowHeight / 2) * scale.height),
                anchor: .center
            )
        }

        // Briefing strip — left: pitch, right: BEST score for highlighted mode.
        let highlighted = modes[state.modeSelectCursor]
        ctx.fillPixel(x: 0, y: 128, width: 256, height: 16,
                      color: palette.lcdShade1, scale: scale)
        ctx.draw(
            Text(highlighted.briefing)
                .font(.system(size: 9 * scale.height,
                              weight: .semibold,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 6 * scale.width, y: 136 * scale.height),
            anchor: .leading
        )
        let best = state.bestScore(for: highlighted)
        if best > 0 {
            ctx.draw(
                Text("BEST \(best)")
                    .font(.system(size: 9 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 250 * scale.width, y: 136 * scale.height),
                anchor: .trailing
            )
        }
    }

    // MARK: - Gameplay scene

    private func renderGame(into ctx: inout GraphicsContext, scale: CGSize) {
        // Side-map background tint: a sparse dot pattern in shade1 so
        // the player can tell at a glance which room they're in.
        if state.mode == .portals && state.inSideMap {
            for row in stride(from: SnakeState.playRowStart, to: SnakeState.playRowEnd, by: 2) {
                for col in stride(from: row % 4, to: SnakeState.cols, by: 4) {
                    ctx.fillPixel(x: col * 8 + 3, y: row * 8 + 3,
                                  width: 2, height: 2,
                                  color: palette.lcdShade1, scale: scale)
                }
            }
        }

        // HUD bar (top 24 px = 3 cells)
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 23,
                      color: palette.lcdShade1, scale: scale)
        ctx.fillPixel(x: 0, y: 23, width: 256, height: 1,
                      color: palette.lcdShade3, scale: scale)

        // SCORE
        ctx.draw(
            Text(String(format: "SCORE  %03d", state.score))
                .font(.system(size: 12 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 6 * scale.width, y: 12 * scale.height),
            anchor: .leading
        )

        // BEST (right side of HUD) — current mode's all-time high.
        let best = state.bestScore(for: state.mode)
        if best > 0 {
            ctx.draw(
                Text(String(format: "BEST %03d", best))
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 134 * scale.width, y: 12 * scale.height),
                anchor: .leading
            )
        }

        // Carry indicator in HUD — when carrying treasure in Portals
        // mode, show the multiplier label so the player remembers the
        // payout they're hauling around.
        if state.mode == .portals && state.isCarryingTreasure {
            ctx.draw(
                Text("\(state.carriedTreasureKind.label)")
                    .font(.system(size: 10 * scale.height,
                                  weight: .black,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 210 * scale.width, y: 12 * scale.height),
                anchor: .leading
            )
        }

        // Mini "alive/dead" indicator on the right of HUD
        let indicatorColor: Color = {
            switch state.phase {
            case .playing: return palette.lcdShade3
            case .paused:  return palette.lcdShade2
            default:       return palette.lcdShade0
            }
        }()
        for dx in [0, 4, 8] {
            ctx.fillPixel(x: 234 + dx, y: 9, width: 3, height: 3,
                          color: indicatorColor, scale: scale)
        }

        // Portals — drawn before the snake so the snake sits on top
        // of the portal sprites.
        if state.mode == .portals {
            drawPortals(into: &ctx, scale: scale)
        }

        // Side-map obstacles + treasure (Portals + inSideMap).
        if state.mode == .portals && state.inSideMap {
            drawSideMapObstacles(into: &ctx, scale: scale)
            drawSideMapTreasure(into: &ctx, scale: scale)
        }

        // Food (small 6×6 within an 8-cell, slightly offset)
        let food = state.food
        ctx.fillPixel(x: food.x * 8 + 1, y: food.y * 8 + 1, width: 6, height: 6,
                      color: palette.lcdShade2, scale: scale)
        ctx.fillPixel(x: food.x * 8 + 2, y: food.y * 8 + 2, width: 4, height: 4,
                      color: palette.lcdShade3, scale: scale)

        // Snake body — head is darker, body shade2
        for (i, segment) in state.snake.enumerated() {
            let color: Color = (i == 0) ? palette.lcdShade3 : palette.lcdShade2
            ctx.fillPixel(x: segment.x * 8 + 1, y: segment.y * 8 + 1,
                          width: 6, height: 6, color: color, scale: scale)
        }

        // Carry sparkle trail + head pulse (Portals + carrying).
        if state.mode == .portals && state.isCarryingTreasure {
            drawCarryIndicator(into: &ctx, scale: scale)
        }

        // Pause / death overlay
        switch state.phase {
        case .paused:
            renderCenteredBanner(into: &ctx, scale: scale,
                                 title: "PAUSED",
                                 subtitle: "A: RESUME  B: MENU")
        case .dead:
            let subtitle = state.isNewBest
                ? "NEW BEST!  A: RETRY"
                : "A: RETRY  START: MENU"
            renderCenteredBanner(into: &ctx, scale: scale,
                                 title: "GAME OVER",
                                 subtitle: subtitle)
        default:
            break
        }
    }

    // MARK: - Portals visuals

    /// Render 1-wide pair-linked teleports (only on the current map's
    /// side) and the active 2-wide gateway. Each 1-wide portal has a
    /// subtle swirling animation; the gateway is drawn as a wider
    /// doorway with corner brackets.
    private func drawPortals(into ctx: inout GraphicsContext, scale: CGSize) {
        // 1-wide pairs only appear on the main map for v1.
        if !state.inSideMap {
            for (a, b) in state.portalPairs {
                drawWarpCell(into: &ctx, scale: scale, cell: a.cells[0], variant: 0)
                drawWarpCell(into: &ctx, scale: scale, cell: b.cells[0], variant: 1)
            }
        }
        // 2-wide gateway — main on the main map, side on the side map.
        let gw = state.inSideMap ? state.sideGateway : state.mainGateway
        if let g = gw {
            drawGateway(into: &ctx, scale: scale, portal: g)
        }
    }

    private func drawWarpCell(
        into ctx: inout GraphicsContext, scale: CGSize,
        cell: SnakeState.GridPoint, variant: Int
    ) {
        let x = cell.x * 8, y = cell.y * 8
        // Border ring
        ctx.fillPixel(x: x, y: y, width: 8, height: 1, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x, y: y + 7, width: 8, height: 1, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x, y: y, width: 1, height: 8, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x + 7, y: y, width: 1, height: 8, color: palette.lcdShade3, scale: scale)
        // Inner pulse — alternates between shade2 and shade1 every
        // few frames, offset by variant so paired endpoints pulse
        // out of phase (visually telegraphing the pairing).
        let frame = (state.animationTick / 10 + variant) % 2
        let fill = (frame == 0) ? palette.lcdShade2 : palette.lcdShade1
        ctx.fillPixel(x: x + 2, y: y + 2, width: 4, height: 4,
                      color: fill, scale: scale)
        ctx.fillPixel(x: x + 3, y: y + 3, width: 2, height: 2,
                      color: palette.lcdShade3, scale: scale)
    }

    private func drawGateway(
        into ctx: inout GraphicsContext, scale: CGSize,
        portal: SnakeState.Portal
    ) {
        let x = portal.x * 8, y = portal.y * 8
        let w = portal.width * 8
        // Doorway outline with corner brackets
        ctx.fillPixel(x: x, y: y, width: w, height: 1, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x, y: y + 7, width: w, height: 1, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x, y: y, width: 1, height: 8, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x + w - 1, y: y, width: 1, height: 8, color: palette.lcdShade3, scale: scale)
        // Inner swirl — 2-cell wide so it reads as a "wider portal".
        let frame = (state.animationTick / 8) % 3
        let innerColor: Color
        switch frame {
        case 0:  innerColor = palette.lcdShade2
        case 1:  innerColor = palette.lcdShade1
        default: innerColor = palette.lcdShade2
        }
        ctx.fillPixel(x: x + 2, y: y + 2, width: w - 4, height: 4,
                      color: innerColor, scale: scale)
        // Bracket accents at the corners (top-inner pair)
        ctx.fillPixel(x: x + 1, y: y + 1, width: 1, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x + w - 2, y: y + 1, width: 1, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x + 1, y: y + 6, width: 1, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x + w - 2, y: y + 6, width: 1, height: 1,
                      color: palette.lcdShade3, scale: scale)
    }

    private func drawSideMapObstacles(into ctx: inout GraphicsContext, scale: CGSize) {
        for o in state.sideMapObstacles {
            let x = o.x * 8, y = o.y * 8
            ctx.fillPixel(x: x + 1, y: y + 1, width: 6, height: 6,
                          color: palette.lcdShade3, scale: scale)
            // Rivet pixels for "industrial" read
            ctx.fillPixel(x: x + 2, y: y + 2, width: 1, height: 1,
                          color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + 5, y: y + 5, width: 1, height: 1,
                          color: palette.lcdShade1, scale: scale)
        }
    }

    /// Treasure sprite + multiplier label. Sprite shape varies by
    /// tier: small pellet for x2 → animated chest for x50.
    private func drawSideMapTreasure(into ctx: inout GraphicsContext, scale: CGSize) {
        guard let t = state.sideMapTreasure else { return }
        let x = t.x * 8, y = t.y * 8
        let kind = state.sideMapTreasureKind
        let twinkle = (state.animationTick / 6) % 3

        switch kind {
        case .x2:
            ctx.fillPixel(x: x + 3, y: y + 3, width: 2, height: 2,
                          color: palette.lcdShade3, scale: scale)
        case .x5:
            ctx.fillPixel(x: x + 2, y: y + 3, width: 4, height: 2,
                          color: palette.lcdShade3, scale: scale)
            if twinkle != 2 {
                ctx.fillPixel(x: x + 1, y: y + 2, width: 1, height: 1,
                              color: palette.lcdShade2, scale: scale)
            }
        case .x10:
            // Star: + shape
            ctx.fillPixel(x: x + 3, y: y + 1, width: 2, height: 6,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 3, width: 6, height: 2,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 3, y: y + 3, width: 2, height: 2,
                          color: palette.lcdShade1, scale: scale)
        case .x20:
            // Diamond
            ctx.fillPixel(x: x + 3, y: y,     width: 2, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 1, width: 4, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 2, width: 6, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x,     y: y + 3, width: 8, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 4, width: 6, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 5, width: 4, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 3, y: y + 6, width: 2, height: 1, color: palette.lcdShade3, scale: scale)
            // Inner sparkle
            if twinkle == 0 {
                ctx.fillPixel(x: x + 3, y: y + 3, width: 2, height: 1, color: palette.lcdShade1, scale: scale)
            }
        case .x50:
            // Crown — bigger sprite with animated sparkle dots
            ctx.fillPixel(x: x,     y: y + 5, width: 8, height: 2, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x,     y: y + 2, width: 1, height: 3, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 3, y: y + 1, width: 2, height: 4, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 7, y: y + 2, width: 1, height: 3, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 5, width: 4, height: 1, color: palette.lcdShade1, scale: scale)
            // Sparkle dots around the crown
            if twinkle != 1 {
                ctx.fillPixel(x: x - 2, y: y, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: x + 9, y: y + 1, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            }
            if twinkle == 2 {
                ctx.fillPixel(x: x + 4, y: y - 2, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            }
        }

        // Multiplier label, drawn just to the right of the sprite.
        // Anchored leading so it can extend off the cell boundary
        // without clipping the sprite itself.
        let labelX = (t.x + 1) * 8 + 1
        let labelY = t.y * 8 + 4
        ctx.draw(
            Text(kind.label)
                .font(.system(size: 8 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: CGFloat(labelX) * scale.width,
                        y: CGFloat(labelY) * scale.height),
            anchor: .leading
        )
    }

    /// Pulsing pixel on top of the snake's head + subtle sparkles
    /// trailing behind, so the player can see they're carrying.
    private func drawCarryIndicator(into ctx: inout GraphicsContext, scale: CGSize) {
        guard let head = state.snake.first else { return }
        let hx = head.x * 8, hy = head.y * 8
        // Pulsing pixel — 2x2 when "lit", 1x1 when dim, on a 4-frame cycle
        let pulse = (state.animationTick / 8) % 2
        if pulse == 0 {
            ctx.fillPixel(x: hx + 2, y: hy - 1, width: 4, height: 2,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: hx + 3, y: hy - 2, width: 2, height: 1,
                          color: palette.lcdShade2, scale: scale)
        } else {
            ctx.fillPixel(x: hx + 3, y: hy - 1, width: 2, height: 1,
                          color: palette.lcdShade3, scale: scale)
        }
        // Subtle sparkles on a couple of body segments behind the head
        let sparkleFrames = (state.animationTick / 5) % 4
        for (i, seg) in state.snake.enumerated() where i > 0 && i % 3 == sparkleFrames {
            let sx = seg.x * 8 + 3, sy = seg.y * 8 + 3
            ctx.fillPixel(x: sx, y: sy, width: 1, height: 1,
                          color: palette.lcdShade3, scale: scale)
        }
    }

    private func renderCenteredBanner(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        title: String,
        subtitle: String
    ) {
        // Dim the playfield (rows 3-17, y=24…143)
        ctx.fillPixel(x: 0, y: 24, width: 256, height: 120,
                      color: palette.lcdShade3.opacity(0.55), scale: scale)
        // Banner box centered horizontally
        let boxX = 48, boxY = 58, boxW = 160, boxH = 40
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: boxH,
                      color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY,                width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY + boxH - 1,     width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)

        ctx.draw(
            Text(title)
                .font(.system(size: 15 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 72 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text(subtitle)
                .font(.system(size: 9 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 88 * scale.height),
            anchor: .center
        )
    }
}

// MARK: - Built-in cartridge factory

public extension GameBoyCartridge {
    /// Built-in Snake. Hosts a mode-select grid with Classic in v1;
    /// additional modes (Portals, Crusher, Gauntlet) plug in as new
    /// cases in `SnakeState.Mode`.
    static let snake = GameBoyCartridge(
        id: "snake",
        title: "SNAKE",
        blurb: "EAT. GROW. AVOID YOURSELF.",
        make: { input in SnakeGame(input: input) }
    )
}
