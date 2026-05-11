import SwiftUI
import GameBoyKit
import ConsoleKit

/// Phase-1 QUESTKID — a small top-down Zelda-like adventure across
/// four connected rooms. Sword combat, wandering enemies, hearts HUD,
/// game-over → retry. Controls:
///
/// - D-pad: walk in 4 directions
/// - A:     swing sword
/// - B:     (reserved for items in Phase 2)
/// - START: (reserved for inventory in Phase 2)
/// - MENU:  return to library (handled by CartridgeShelf)
public struct QuestKidGame: View {

    public let input: GameBoyInput
    @State private var state: QuestKidState
    @State private var resetCounter: Int = 0
    @State private var swingPending: Bool = false   // edge-trigger A-button
    @Environment(\.gameBoyPalette) private var palette
    @Environment(\.gameBoyPowerOn) private var powerOn

    public init(input: GameBoyInput) {
        self.input = input
        _state = State(initialValue: QuestKidState())
    }

    public var body: some View {
        // TimelineView just drives re-renders. All mutation happens in
        // the .task tick loop below so we never mutate state inside the
        // view body (which would crash with "Modifying state during view
        // update" runtime warnings).
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !powerOn)) { _ in
            PixelCanvas { ctx, scale in
                renderFrame(into: &ctx, scale: scale)
            }
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard powerOn, pressed else { return }
            if state.phase == .gameOver {
                state.reset()
                resetCounter &+= 1
            } else {
                swingPending = true
            }
        }
        .task(id: "\(resetCounter)-\(powerOn)") {
            guard powerOn else { return }
            await runTickLoop()
        }
    }

    // MARK: - Tick loop (mutation lives here, not in body)

    private func runTickLoop() async {
        let interval: TimeInterval = 1.0 / 60.0
        var lastTick = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            let now = Date()
            let dt = min(0.05, now.timeIntervalSince(lastTick))
            lastTick = now

            // Drive simulation.
            let dpad = currentDpad()
            let swung = swingPending
            swingPending = false
            state.tick(dt: dt, dpad: dpad, swingPressed: swung)
        }
    }

    // MARK: - Render (pure function of state)

    private func renderFrame(into ctx: inout GraphicsContext, scale: CGSize) {
        // Background
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                      color: palette.lcdShade0, scale: scale)

        // HUD (top 16 px)
        renderHUD(into: &ctx, scale: scale)

        // Room transition: slide the two rooms past each other.
        if case .roomTransition(let from, let to, let progress, let dir) = state.phase {
            renderRoomTransition(into: &ctx, scale: scale,
                                 from: from, to: to,
                                 progress: progress, dir: dir)
            return
        }

        // Normal play: room + entities.
        renderRoom(into: &ctx, scale: scale,
                   room: state.currentRoom,
                   pixelOffsetX: 0, pixelOffsetY: QuestKidLayout.hudHeight)
        renderEnemies(into: &ctx, scale: scale,
                      enemies: state.currentEnemies,
                      pixelOffsetX: 0, pixelOffsetY: QuestKidLayout.hudHeight)
        renderPlayer(into: &ctx, scale: scale,
                     pixelOffsetX: 0, pixelOffsetY: QuestKidLayout.hudHeight)
        renderSword(into: &ctx, scale: scale,
                    pixelOffsetX: 0, pixelOffsetY: QuestKidLayout.hudHeight)

        if state.phase == .gameOver {
            renderGameOver(into: &ctx, scale: scale)
        }
    }

    private func currentDpad() -> Direction? {
        guard let raw = input.dpad else { return nil }
        // Reduce 8-way → 4-way (priority: vertical when ambiguous).
        if raw.isUp    { return .up }
        if raw.isDown  { return .down }
        if raw.isLeft  { return .left }
        if raw.isRight { return .right }
        return nil
    }

    // MARK: - HUD

    private func renderHUD(into ctx: inout GraphicsContext, scale: CGSize) {
        // Black strip.
        ctx.fillPixel(x: 0, y: 0, width: 256, height: QuestKidLayout.hudHeight,
                      color: palette.lcdShade3, scale: scale)
        // Bottom 1-px separator.
        ctx.fillPixel(x: 0, y: QuestKidLayout.hudHeight - 1, width: 256, height: 1,
                      color: palette.lcdShade2, scale: scale)

        // Hearts (half-heart resolution).
        let fullHearts = state.player.hp / 2
        let halfHeart  = state.player.hp % 2 == 1
        let totalSlots = state.player.maxHP / 2
        for i in 0..<totalSlots {
            let x = 6 + i * 14
            let y = 3
            // Empty heart frame
            drawHeart(into: &ctx, scale: scale, x: x, y: y, fill: .empty)
            if i < fullHearts {
                drawHeart(into: &ctx, scale: scale, x: x, y: y, fill: .full)
            } else if i == fullHearts, halfHeart {
                drawHeart(into: &ctx, scale: scale, x: x, y: y, fill: .half)
            }
        }

        // "QUESTKID" title on the right.
        ctx.draw(
            Text("QUESTKID")
                .font(.system(size: 10 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade0),
            at: CGPoint(x: 250 * scale.width, y: 8 * scale.height),
            anchor: .trailing
        )
    }

    private enum HeartFill { case empty, half, full }

    private func drawHeart(into ctx: inout GraphicsContext, scale: CGSize,
                           x: Int, y: Int, fill: HeartFill) {
        // 10×10 chunky heart. Outline = lcdShade0 (visible on dark HUD).
        // Fill = lcdShade1 (medium) for half, lcdShade2 (dark-ish) for empty,
        // bright shade for full — using a warm tint so it pops on the
        // shade3 HUD.
        let outline = palette.lcdShade0
        let fillColor: Color
        switch fill {
        case .empty: fillColor = palette.lcdShade3
        case .half:  fillColor = palette.lcdShade1
        case .full:  fillColor = palette.lcdShade0
        }
        // Draw heart pixel-by-pixel from a small bitmap.
        // 1 = outline, 2 = fill, 0 = transparent
        let heart: [[Int]] = [
            [0,1,1,0,0,0,1,1,0,0],
            [1,2,2,1,0,1,2,2,1,0],
            [1,2,2,2,1,2,2,2,1,0],
            [1,2,2,2,2,2,2,2,1,0],
            [0,1,2,2,2,2,2,1,0,0],
            [0,0,1,2,2,2,1,0,0,0],
            [0,0,0,1,2,1,0,0,0,0],
            [0,0,0,0,1,0,0,0,0,0],
        ]
        for (row, line) in heart.enumerated() {
            for (col, v) in line.enumerated() {
                guard v != 0 else { continue }
                let color: Color = v == 1 ? outline : fillColor
                ctx.fillPixel(x: x + col, y: y + row, color: color, scale: scale)
            }
        }
        // Half-heart: blank out the right half of the fill.
        if fill == .half {
            for row in 1..<heart.count {
                let line = heart[row]
                for col in 5..<line.count where line[col] == 2 {
                    ctx.fillPixel(x: x + col, y: y + row, color: palette.lcdShade3, scale: scale)
                }
            }
        }
    }

    // MARK: - Room

    private func renderRoom(
        into ctx: inout GraphicsContext, scale: CGSize,
        room: Room, pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        for row in 0..<QuestKidLayout.roomRows {
            for col in 0..<QuestKidLayout.roomCols {
                let tile = room.tile(col: col, row: row)
                let x = pixelOffsetX + col * QuestKidLayout.tileSize
                let y = pixelOffsetY + row * QuestKidLayout.tileSize
                drawTile(into: &ctx, scale: scale, x: x, y: y, tile: tile)
            }
        }
    }

    private func drawTile(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, tile: TileKind
    ) {
        let t = QuestKidLayout.tileSize
        switch tile {
        case .grass:
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade0, scale: scale)
            // tiny tufts of "grass" pixels for texture
            ctx.fillPixel(x: x + 3,  y: y + 5,  color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + 11, y: y + 10, color: palette.lcdShade1, scale: scale)

        case .sand:
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade0, scale: scale)
            // sand stipple slightly darker than grass-tuft
            ctx.fillPixel(x: x + 4,  y: y + 3,  color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + 12, y: y + 7,  color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + 6,  y: y + 12, color: palette.lcdShade1, scale: scale)

        case .rock:
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade2, scale: scale)
            // dark outline + highlight
            ctx.fillPixel(x: x, y: y, width: t, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x, y: y + t - 1, width: t, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x, y: y, width: 1, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + t - 1, y: y, width: 1, height: t, color: palette.lcdShade3, scale: scale)
            // highlight
            ctx.fillPixel(x: x + 2, y: y + 2, width: 4, height: 2, color: palette.lcdShade1, scale: scale)

        case .tree:
            // Grass underneath
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade0, scale: scale)
            // Trunk
            ctx.fillPixel(x: x + 7, y: y + 11, width: 3, height: 5, color: palette.lcdShade3, scale: scale)
            // Foliage
            ctx.fillPixel(x: x + 2,  y: y + 2,  width: 12, height: 10, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x + 4,  y: y + 4,  width: 8,  height: 6,  color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 5,  y: y + 5,  width: 2,  height: 2,  color: palette.lcdShade1, scale: scale)

        case .water:
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 4, width: 5, height: 1, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + 8, y: y + 9, width: 5, height: 1, color: palette.lcdShade1, scale: scale)

        case .door:
            // Render as floor (walkable) with a subtle "doorway" mark.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + 6, y: y + 6, width: 4, height: 4, color: palette.lcdShade0, scale: scale)
        }
    }

    // MARK: - Player

    private func renderPlayer(
        into ctx: inout GraphicsContext, scale: CGSize,
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        // Flicker during iframes.
        if state.player.iframes > 0 {
            let phase = Int(state.player.iframes * 16) % 2
            if phase == 0 { return }
        }
        let px = pixelOffsetX + Int(state.player.x)
        let py = pixelOffsetY + Int(state.player.y)
        drawPlayerSprite(into: &ctx, scale: scale, x: px, y: py, facing: state.player.facing)
    }

    /// Hand-drawn 16×16 player sprite per facing direction. Shades:
    ///   - lcdShade3 = body / outline (the "color" of the character)
    ///   - lcdShade2 = highlight / face
    ///   - lcdShade1 = ambient detail
    /// We share the body silhouette across directions and differentiate
    /// the head/face to indicate facing.
    private func drawPlayerSprite(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, facing: Direction
    ) {
        let body  = palette.lcdShade3
        let trim  = palette.lcdShade2
        let face  = palette.lcdShade1

        // Common body shape (a stocky tunic + legs).
        // tunic torso
        ctx.fillPixel(x: x + 4, y: y + 8, width: 8, height: 6, color: body, scale: scale)
        // belt
        ctx.fillPixel(x: x + 4, y: y + 12, width: 8, height: 1, color: trim, scale: scale)
        // legs
        ctx.fillPixel(x: x + 4, y: y + 14, width: 3, height: 2, color: body, scale: scale)
        ctx.fillPixel(x: x + 9, y: y + 14, width: 3, height: 2, color: body, scale: scale)

        // Direction-specific head/face.
        switch facing {
        case .down:
            // round head with 2 eyes
            ctx.fillPixel(x: x + 4, y: y + 2, width: 8, height: 6, color: body, scale: scale)
            ctx.fillPixel(x: x + 5, y: y + 4, width: 6, height: 3, color: face, scale: scale)
            ctx.fillPixel(x: x + 6, y: y + 5, color: body, scale: scale)
            ctx.fillPixel(x: x + 9, y: y + 5, color: body, scale: scale)
        case .up:
            // back of head — no face details
            ctx.fillPixel(x: x + 4, y: y + 2, width: 8, height: 6, color: body, scale: scale)
            ctx.fillPixel(x: x + 5, y: y + 3, width: 6, height: 2, color: trim, scale: scale)
        case .left:
            ctx.fillPixel(x: x + 4, y: y + 2, width: 8, height: 6, color: body, scale: scale)
            ctx.fillPixel(x: x + 5, y: y + 4, width: 4, height: 3, color: face, scale: scale)
            ctx.fillPixel(x: x + 5, y: y + 5, color: body, scale: scale)
        case .right:
            ctx.fillPixel(x: x + 4, y: y + 2, width: 8, height: 6, color: body, scale: scale)
            ctx.fillPixel(x: x + 7, y: y + 4, width: 4, height: 3, color: face, scale: scale)
            ctx.fillPixel(x: x + 10, y: y + 5, color: body, scale: scale)
        }
    }

    private func renderSword(
        into ctx: inout GraphicsContext, scale: CGSize,
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        guard state.player.swordTimer > 0 else { return }
        let px = pixelOffsetX + Int(state.player.x)
        let py = pixelOffsetY + Int(state.player.y)
        let blade = palette.lcdShade2
        let edge  = palette.lcdShade3
        switch state.player.facing {
        case .up:
            ctx.fillPixel(x: px + 7, y: py - 12, width: 2, height: 12, color: blade, scale: scale)
            ctx.fillPixel(x: px + 7, y: py - 12, width: 2, height: 2,  color: edge,  scale: scale)
        case .down:
            ctx.fillPixel(x: px + 7, y: py + 16, width: 2, height: 12, color: blade, scale: scale)
            ctx.fillPixel(x: px + 7, y: py + 26, width: 2, height: 2,  color: edge,  scale: scale)
        case .left:
            ctx.fillPixel(x: px - 12, y: py + 7, width: 12, height: 2, color: blade, scale: scale)
            ctx.fillPixel(x: px - 12, y: py + 7, width: 2,  height: 2, color: edge,  scale: scale)
        case .right:
            ctx.fillPixel(x: px + 16, y: py + 7, width: 12, height: 2, color: blade, scale: scale)
            ctx.fillPixel(x: px + 26, y: py + 7, width: 2,  height: 2, color: edge,  scale: scale)
        }
    }

    // MARK: - Enemies

    private func renderEnemies(
        into ctx: inout GraphicsContext, scale: CGSize,
        enemies: [Enemy],
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        for e in enemies {
            let x = pixelOffsetX + Int(e.x)
            let y = pixelOffsetY + Int(e.y)
            // Flash white-ish when freshly hit.
            let bodyColor = e.hitFlash > 0 ? palette.lcdShade0 : palette.lcdShade2
            let outlineColor = palette.lcdShade3
            // Body
            ctx.fillPixel(x: x + 3, y: y + 5, width: 10, height: 9, color: bodyColor, scale: scale)
            // Tentacle-like legs
            ctx.fillPixel(x: x + 2, y: y + 13, width: 2, height: 3, color: bodyColor, scale: scale)
            ctx.fillPixel(x: x + 12, y: y + 13, width: 2, height: 3, color: bodyColor, scale: scale)
            ctx.fillPixel(x: x + 7, y: y + 13, width: 2, height: 3, color: bodyColor, scale: scale)
            // Head highlight
            ctx.fillPixel(x: x + 5, y: y + 7, width: 6, height: 2, color: outlineColor, scale: scale)
            // Eyes
            ctx.fillPixel(x: x + 6, y: y + 7, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x + 9, y: y + 7, color: palette.lcdShade0, scale: scale)
        }
    }

    // MARK: - Game over

    private func renderGameOver(into ctx: inout GraphicsContext, scale: CGSize) {
        // Dim the world.
        ctx.fillPixel(x: 0, y: QuestKidLayout.hudHeight,
                      width: 256, height: 128,
                      color: palette.lcdShade3.opacity(0.6), scale: scale)
        // Banner
        ctx.fillPixel(x: 48, y: 56, width: 160, height: 36,
                      color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: 48, y: 56, width: 160, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: 48, y: 91, width: 160, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.draw(
            Text("GAME OVER")
                .font(.system(size: 14 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 68 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text("A: RETRY   MENU: LIBRARY")
                .font(.system(size: 8 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 84 * scale.height),
            anchor: .center
        )
    }

    // MARK: - Room transition

    private func renderRoomTransition(
        into ctx: inout GraphicsContext, scale: CGSize,
        from: Int, to: Int, progress: Double, dir: Direction
    ) {
        // Slide rooms in `dir` direction. We render two rooms side-by-side
        // and the world shifts by `progress * playWidth/Height`.
        let pw = QuestKidLayout.playWidth
        let ph = QuestKidLayout.playHeight
        let p  = max(0, min(1, progress))
        var fromOffX = 0, fromOffY = 0
        var toOffX = 0, toOffY = 0
        switch dir {
        case .right: fromOffX = -Int(Double(pw) * p); toOffX = pw - Int(Double(pw) * p)
        case .left:  fromOffX =  Int(Double(pw) * p); toOffX = -pw + Int(Double(pw) * p)
        case .down:  fromOffY = -Int(Double(ph) * p); toOffY = ph - Int(Double(ph) * p)
        case .up:    fromOffY =  Int(Double(ph) * p); toOffY = -ph + Int(Double(ph) * p)
        }
        let hud = QuestKidLayout.hudHeight
        renderRoom(into: &ctx, scale: scale,
                   room: state.rooms[from],
                   pixelOffsetX: fromOffX, pixelOffsetY: hud + fromOffY)
        renderRoom(into: &ctx, scale: scale,
                   room: state.rooms[to],
                   pixelOffsetX: toOffX,   pixelOffsetY: hud + toOffY)
        // Player rides along with the "from" room.
        renderPlayer(into: &ctx, scale: scale,
                     pixelOffsetX: fromOffX, pixelOffsetY: hud + fromOffY)
    }
}

// MARK: - Cartridge factory

public extension GameBoyCartridge {
    /// Built-in: QUESTKID — a tiny top-down adventure across 4 rooms.
    static let questKid = GameBoyCartridge(
        id: "questkid",
        title: "QUESTKID",
        blurb: "FOUR ROOMS. ONE SWORD. NO MERCY.",
        make: { input in QuestKidGame(input: input) }
    )
}
