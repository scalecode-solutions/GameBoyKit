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
            switch state.phase {
            case .title:
                state.start()
            case .gameOver, .won:
                state.reset()
                resetCounter &+= 1
            default:
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

        // Title screen short-circuits the rest of the render.
        if state.phase == .title {
            renderTitle(into: &ctx, scale: scale)
            return
        }

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
        let hud = QuestKidLayout.hudHeight
        renderRoom(into: &ctx, scale: scale,
                   room: state.currentRoom,
                   pixelOffsetX: 0, pixelOffsetY: hud)
        renderHearts(into: &ctx, scale: scale,
                     hearts: state.currentHearts,
                     pixelOffsetX: 0, pixelOffsetY: hud)
        renderKeys(into: &ctx, scale: scale,
                   keys: state.currentKeys,
                   pixelOffsetX: 0, pixelOffsetY: hud)
        renderEnemies(into: &ctx, scale: scale,
                      enemies: state.currentEnemies,
                      pixelOffsetX: 0, pixelOffsetY: hud)
        renderProjectiles(into: &ctx, scale: scale,
                          projectiles: state.currentProjectiles,
                          pixelOffsetX: 0, pixelOffsetY: hud)
        renderPlayer(into: &ctx, scale: scale,
                     pixelOffsetX: 0, pixelOffsetY: hud)
        renderSword(into: &ctx, scale: scale,
                    pixelOffsetX: 0, pixelOffsetY: hud)

        if state.phase == .gameOver {
            renderGameOver(into: &ctx, scale: scale)
        } else if state.phase == .won {
            renderWin(into: &ctx, scale: scale)
        }

        // HUD key indicator if player has the key.
        if state.player.hasKey {
            renderKeyIndicator(into: &ctx, scale: scale)
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

        case .stone:
            // Dungeon floor — darker than grass, with subtle grout lines.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x, y: y + t - 1, width: t, height: 1, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x + t - 1, y: y, width: 1, height: t, color: palette.lcdShade2, scale: scale)

        case .wallDark:
            // Dungeon wall — slate with chunky brick outline.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: t - 2, height: t - 2, color: palette.lcdShade2, scale: scale)
            // Horizontal seams
            ctx.fillPixel(x: x, y: y + 7,  width: t, height: 1, color: palette.lcdShade3, scale: scale)

        case .lockedDoor:
            // Heavy stone arch with a visible padlock.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 2, width: t - 4, height: t - 4, color: palette.lcdShade2, scale: scale)
            // Padlock shackle
            ctx.fillPixel(x: x + 6, y: y + 5, width: 4, height: 1, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x + 6, y: y + 6, width: 1, height: 2, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x + 9, y: y + 6, width: 1, height: 2, color: palette.lcdShade0, scale: scale)
            // Padlock body
            ctx.fillPixel(x: x + 5, y: y + 8, width: 6, height: 5, color: palette.lcdShade0, scale: scale)
            // Keyhole
            ctx.fillPixel(x: x + 7, y: y + 10, width: 2, height: 2, color: palette.lcdShade3, scale: scale)
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

        // Map remaining time → swing progress 0..<1. Higher swordTimer
        // = earlier in the swing.
        let remaining = state.player.swordTimer
        let total = QuestKidState.swordDuration
        let progress = max(0, min(1, 1.0 - remaining / total))
        // 3-frame arc: 0-0.33 anticipation, 0.33-0.66 strike, 0.66-1 recovery
        let frame = progress < 0.33 ? 0 : (progress < 0.66 ? 1 : 2)

        switch state.player.facing {
        case .up:
            // Arc sweeps left → up → right across the top of the player.
            switch frame {
            case 0:
                // Pulled to the left
                ctx.fillPixel(x: px - 2, y: py + 4, width: 2, height: 8, color: blade, scale: scale)
                ctx.fillPixel(x: px - 2, y: py + 4, width: 2, height: 2, color: edge,  scale: scale)
            case 1:
                // Straight up — full extent
                ctx.fillPixel(x: px + 7, y: py - 12, width: 2, height: 12, color: blade, scale: scale)
                ctx.fillPixel(x: px + 7, y: py - 12, width: 2, height: 2,  color: edge,  scale: scale)
                // Wide sweep marks
                ctx.fillPixel(x: px + 1, y: py - 2, width: 14, height: 1, color: blade.opacity(0.7), scale: scale)
            default:
                // Following through to the right
                ctx.fillPixel(x: px + 16, y: py + 4, width: 2, height: 8, color: blade, scale: scale)
                ctx.fillPixel(x: px + 16, y: py + 4, width: 2, height: 2, color: edge,  scale: scale)
            }
        case .down:
            switch frame {
            case 0:
                ctx.fillPixel(x: px + 16, y: py + 4, width: 2, height: 8, color: blade, scale: scale)
                ctx.fillPixel(x: px + 16, y: py + 10, width: 2, height: 2, color: edge,  scale: scale)
            case 1:
                ctx.fillPixel(x: px + 7, y: py + 16, width: 2, height: 12, color: blade, scale: scale)
                ctx.fillPixel(x: px + 7, y: py + 26, width: 2, height: 2,  color: edge,  scale: scale)
                ctx.fillPixel(x: px + 1, y: py + 18, width: 14, height: 1, color: blade.opacity(0.7), scale: scale)
            default:
                ctx.fillPixel(x: px - 2, y: py + 4, width: 2, height: 8, color: blade, scale: scale)
                ctx.fillPixel(x: px - 2, y: py + 10, width: 2, height: 2, color: edge,  scale: scale)
            }
        case .left:
            switch frame {
            case 0:
                ctx.fillPixel(x: px + 4, y: py - 2, width: 8, height: 2, color: blade, scale: scale)
                ctx.fillPixel(x: px + 4, y: py - 2, width: 2, height: 2, color: edge,  scale: scale)
            case 1:
                ctx.fillPixel(x: px - 12, y: py + 7, width: 12, height: 2, color: blade, scale: scale)
                ctx.fillPixel(x: px - 12, y: py + 7, width: 2,  height: 2, color: edge,  scale: scale)
                ctx.fillPixel(x: px - 2, y: py + 1, width: 1, height: 14, color: blade.opacity(0.7), scale: scale)
            default:
                ctx.fillPixel(x: px + 4, y: py + 16, width: 8, height: 2, color: blade, scale: scale)
                ctx.fillPixel(x: px + 4, y: py + 16, width: 2, height: 2, color: edge,  scale: scale)
            }
        case .right:
            switch frame {
            case 0:
                ctx.fillPixel(x: px + 4, y: py + 16, width: 8, height: 2, color: blade, scale: scale)
                ctx.fillPixel(x: px + 10, y: py + 16, width: 2, height: 2, color: edge,  scale: scale)
            case 1:
                ctx.fillPixel(x: px + 16, y: py + 7, width: 12, height: 2, color: blade, scale: scale)
                ctx.fillPixel(x: px + 26, y: py + 7, width: 2,  height: 2, color: edge,  scale: scale)
                ctx.fillPixel(x: px + 18, y: py + 1, width: 1, height: 14, color: blade.opacity(0.7), scale: scale)
            default:
                ctx.fillPixel(x: px + 4, y: py - 2, width: 8, height: 2, color: blade, scale: scale)
                ctx.fillPixel(x: px + 10, y: py - 2, width: 2, height: 2, color: edge,  scale: scale)
            }
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
            switch e.kind {
            case .octorock: drawOctorock(into: &ctx, scale: scale, x: x, y: y, e: e)
            case .shooter:  drawShooter(into:  &ctx, scale: scale, x: x, y: y, e: e)
            case .charger:  drawCharger(into:  &ctx, scale: scale, x: x, y: y, e: e)
            case .boss:     drawBoss(into:     &ctx, scale: scale, x: x, y: y, e: e)
            }
        }
    }

    private func drawOctorock(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, e: Enemy
    ) {
        let bodyColor = e.hitFlash > 0 ? palette.lcdShade0 : palette.lcdShade2
        let outlineColor = palette.lcdShade3
        ctx.fillPixel(x: x + 3,  y: y + 5,  width: 10, height: 9, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 2,  y: y + 13, width: 2,  height: 3, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 12, y: y + 13, width: 2,  height: 3, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 7,  y: y + 13, width: 2,  height: 3, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 5,  y: y + 7,  width: 6,  height: 2, color: outlineColor, scale: scale)
        ctx.fillPixel(x: x + 6,  y: y + 7,  color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: x + 9,  y: y + 7,  color: palette.lcdShade0, scale: scale)
    }

    /// Shooter — stocky, plant-like turret. Squat base + barrel pointing
    /// in the facing direction.
    private func drawShooter(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, e: Enemy
    ) {
        let bodyColor = e.hitFlash > 0 ? palette.lcdShade0 : palette.lcdShade3
        let trim = palette.lcdShade2
        // Wide squat base
        ctx.fillPixel(x: x + 1,  y: y + 9,  width: 14, height: 6, color: bodyColor, scale: scale)
        // Cap
        ctx.fillPixel(x: x + 3,  y: y + 5,  width: 10, height: 4, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 4,  y: y + 6,  width: 8,  height: 2, color: trim, scale: scale)
        // Eye dot center
        ctx.fillPixel(x: x + 7,  y: y + 11, width: 2,  height: 2, color: palette.lcdShade0, scale: scale)
        // Barrel — points in facing direction
        switch e.facing {
        case .up:    ctx.fillPixel(x: x + 7, y: y + 1, width: 2, height: 5, color: bodyColor, scale: scale)
        case .down:  ctx.fillPixel(x: x + 7, y: y + 14, width: 2, height: 2, color: bodyColor, scale: scale)
        case .left:  ctx.fillPixel(x: x,     y: y + 10, width: 3, height: 2, color: bodyColor, scale: scale)
        case .right: ctx.fillPixel(x: x + 13, y: y + 10, width: 3, height: 2, color: bodyColor, scale: scale)
        }
    }

    /// Charger — taller humanoid silhouette, more aggressive look.
    /// Slightly different proportion from octorock so it reads distinct.
    private func drawCharger(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, e: Enemy
    ) {
        let bodyColor = e.hitFlash > 0 ? palette.lcdShade0 : palette.lcdShade3
        let trim = palette.lcdShade2
        // Body
        ctx.fillPixel(x: x + 4, y: y + 6,  width: 8, height: 8, color: bodyColor, scale: scale)
        // Head (smaller, blockier than player)
        ctx.fillPixel(x: x + 5, y: y + 2,  width: 6, height: 4, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 5, y: y + 3,  width: 6, height: 1, color: trim, scale: scale)
        // Eyes (angry slits)
        ctx.fillPixel(x: x + 6, y: y + 4,  width: 1, height: 1, color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: x + 9, y: y + 4,  width: 1, height: 1, color: palette.lcdShade0, scale: scale)
        // Legs
        ctx.fillPixel(x: x + 4, y: y + 14, width: 3, height: 2, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 9, y: y + 14, width: 3, height: 2, color: bodyColor, scale: scale)
        // Charging visual cue — a bright outline tick on the facing edge
        if e.isCharging {
            switch e.facing {
            case .up:    ctx.fillPixel(x: x + 5, y: y + 1, width: 6, height: 1, color: palette.lcdShade0, scale: scale)
            case .down:  ctx.fillPixel(x: x + 4, y: y + 15, width: 8, height: 1, color: palette.lcdShade0, scale: scale)
            case .left:  ctx.fillPixel(x: x + 3, y: y + 6, width: 1, height: 8, color: palette.lcdShade0, scale: scale)
            case .right: ctx.fillPixel(x: x + 12, y: y + 6, width: 1, height: 8, color: palette.lcdShade0, scale: scale)
            }
        }
    }

    /// Boss sprite — 32×32. Larger silhouette, two horns, glowing eyes
    /// that go red in enraged mode (low HP), pulsing visual when about
    /// to charge.
    private func drawBoss(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, e: Enemy
    ) {
        let enraged = e.hp <= QuestKidState.bossEnrageHPThreshold
        let isTelegraphing = e.telegraphTimer > 0
        // Pulsing white-on/off during wind-up. Frequency ramps up as
        // the wind-up nears completion.
        let telegraphPhase: Int = {
            guard isTelegraphing else { return 0 }
            let nearing = 1.0 - max(0, e.telegraphTimer / 0.6)   // 0..~1
            let freq = 8.0 + nearing * 12.0
            return Int(Date().timeIntervalSinceReferenceDate * freq) % 2
        }()
        let bodyColor: Color = e.hitFlash > 0
            ? palette.lcdShade0
            : (isTelegraphing && telegraphPhase == 0
                ? palette.lcdShade0
                : palette.lcdShade3)
        let mid = palette.lcdShade2
        // Body (chunky 28×24)
        ctx.fillPixel(x: x + 2,  y: y + 6,  width: 28, height: 22, color: bodyColor, scale: scale)
        // Highlight band
        ctx.fillPixel(x: x + 4,  y: y + 10, width: 24, height: 4,  color: mid, scale: scale)
        // Horns
        ctx.fillPixel(x: x + 2,  y: y + 2,  width: 4,  height: 6,  color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 26, y: y + 2,  width: 4,  height: 6,  color: bodyColor, scale: scale)
        ctx.fillPixel(x: x,      y: y,      width: 3,  height: 4,  color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 29, y: y,      width: 3,  height: 4,  color: bodyColor, scale: scale)
        // Eyes (brighter when enraged)
        let eyeColor: Color = enraged ? palette.lcdShade0 : palette.lcdShade1
        ctx.fillPixel(x: x + 8,  y: y + 14, width: 4, height: 3, color: eyeColor, scale: scale)
        ctx.fillPixel(x: x + 20, y: y + 14, width: 4, height: 3, color: eyeColor, scale: scale)
        // Pupil dots
        ctx.fillPixel(x: x + 9,  y: y + 15, width: 2, height: 2, color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: x + 21, y: y + 15, width: 2, height: 2, color: palette.lcdShade3, scale: scale)
        // Maw
        ctx.fillPixel(x: x + 10, y: y + 22, width: 12, height: 3, color: palette.lcdShade2, scale: scale)
        ctx.fillPixel(x: x + 12, y: y + 23, width: 2, height: 1,  color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: x + 18, y: y + 23, width: 2, height: 1,  color: palette.lcdShade0, scale: scale)
        // Stubby legs
        ctx.fillPixel(x: x + 4,  y: y + 28, width: 6, height: 4, color: bodyColor, scale: scale)
        ctx.fillPixel(x: x + 22, y: y + 28, width: 6, height: 4, color: bodyColor, scale: scale)
        // Charging cue — outline on facing edge during charge OR
        // during the charge wind-up.
        let showChargeEdge = e.isCharging
            || (e.telegraphTimer > 0 && e.pendingAttack == .charge)
        if showChargeEdge {
            switch e.facing {
            case .up:    ctx.fillPixel(x: x + 4, y: y, width: 24, height: 1, color: palette.lcdShade0, scale: scale)
            case .down:  ctx.fillPixel(x: x + 4, y: y + 31, width: 24, height: 1, color: palette.lcdShade0, scale: scale)
            case .left:  ctx.fillPixel(x: x, y: y + 4, width: 1, height: 24, color: palette.lcdShade0, scale: scale)
            case .right: ctx.fillPixel(x: x + 31, y: y + 4, width: 1, height: 24, color: palette.lcdShade0, scale: scale)
            }
        }
        // Fan-shot tell — 3 tiny dots arc above the boss during fan wind-up.
        if e.telegraphTimer > 0, e.pendingAttack == .fanShot {
            let aboveY = y - 3
            ctx.fillPixel(x: x + 14, y: aboveY,     width: 4, height: 2, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x + 6,  y: aboveY + 1, width: 2, height: 2, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x + 26, y: aboveY + 1, width: 2, height: 2, color: palette.lcdShade0, scale: scale)
        }
    }

    // MARK: - Projectiles

    private func renderProjectiles(
        into ctx: inout GraphicsContext, scale: CGSize,
        projectiles: [Projectile],
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        let inner = palette.lcdShade3
        let outer = palette.lcdShade2
        for p in projectiles {
            let x = pixelOffsetX + Int(p.x)
            let y = pixelOffsetY + Int(p.y)
            // 6×6 rock pixel:
            //   . X X .
            //   X X X X
            //   X X X X
            //   . X X .
            ctx.fillPixel(x: x + 1, y: y,     width: 4, height: 1, color: outer, scale: scale)
            ctx.fillPixel(x: x,     y: y + 1, width: 6, height: 4, color: outer, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 5, width: 4, height: 1, color: outer, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 2, width: 2, height: 2, color: inner, scale: scale)
        }
    }

    // MARK: - Heart pickups

    private func renderHearts(
        into ctx: inout GraphicsContext, scale: CGSize,
        hearts: [HeartPickup],
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        // Tiny bob animation: y +/- 1 px on a sine cycle.
        let outline = palette.lcdShade3
        let fill = palette.lcdShade2
        let highlight = palette.lcdShade0
        for h in hearts {
            // Despawn flicker on the last 2 seconds.
            if h.ttl < 2 {
                let phase = Int(h.ttl * 8) % 2
                if phase == 0 { continue }
            }
            let bob = Int(round(sin(h.bobPhase * 4) * 1))
            let x = pixelOffsetX + Int(h.x)
            let y = pixelOffsetY + Int(h.y) + bob
            // 8×7 heart shape
            let bits: [[Int]] = [
                [0,1,1,0,0,1,1,0],
                [1,2,2,1,1,2,2,1],
                [1,2,2,2,2,2,2,1],
                [1,2,2,2,2,2,2,1],
                [0,1,2,2,2,2,1,0],
                [0,0,1,2,2,1,0,0],
                [0,0,0,1,1,0,0,0],
            ]
            for (row, line) in bits.enumerated() {
                for (col, v) in line.enumerated() where v != 0 {
                    let c: Color = v == 1 ? outline : fill
                    ctx.fillPixel(x: x + col, y: y + row, color: c, scale: scale)
                }
            }
            // Sparkle highlight
            ctx.fillPixel(x: x + 2, y: y + 2, color: highlight, scale: scale)
        }
    }

    // MARK: - Title screen

    private func renderTitle(into ctx: inout GraphicsContext, scale: CGSize) {
        // Olive base
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                      color: palette.lcdShade0, scale: scale)
        // Top + bottom bars
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 12,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: 0, y: 132, width: 256, height: 12,
                      color: palette.lcdShade3, scale: scale)

        // Title
        ctx.draw(
            Text("QUESTKID")
                .font(.system(size: 26 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 46 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text("FOUR ROOMS. ONE SWORD.")
                .font(.system(size: 8 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 64 * scale.height),
            anchor: .center
        )

        // Decorative sword glyph centered below subtitle
        renderSwordGlyph(into: &ctx, scale: scale, centerX: 128, centerY: 84)

        // Saved record line
        if state.record.cleared {
            let halfHearts = state.record.bestHearts
            let full = halfHearts / 2
            let halfStr = halfHearts % 2 == 1 ? ".5" : ""
            ctx.draw(
                Text("✓ CLEARED  ·  BEST: \(full)\(halfStr) HEARTS")
                    .font(.system(size: 9 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 108 * scale.height),
                anchor: .center
            )
        }

        // Prompt — slow blink
        let blink = Int(Date().timeIntervalSinceReferenceDate * 1.6) % 2 == 0
        if blink {
            ctx.draw(
                Text("PRESS A TO START")
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 122 * scale.height),
                anchor: .center
            )
        }
    }

    private func renderSwordGlyph(
        into ctx: inout GraphicsContext, scale: CGSize,
        centerX: Int, centerY: Int
    ) {
        let blade = palette.lcdShade3
        let hilt = palette.lcdShade2
        let edge = palette.lcdShade0
        // 5-pixel-wide blade pointing up, 20 px tall
        ctx.fillPixel(x: centerX - 1, y: centerY - 10, width: 3, height: 14, color: blade, scale: scale)
        // Edge highlight (left side of blade)
        ctx.fillPixel(x: centerX - 1, y: centerY - 9, width: 1, height: 10, color: edge, scale: scale)
        // Hilt cross-guard
        ctx.fillPixel(x: centerX - 4, y: centerY + 4, width: 9, height: 2, color: hilt, scale: scale)
        // Handle
        ctx.fillPixel(x: centerX - 1, y: centerY + 6, width: 3, height: 4, color: hilt, scale: scale)
        // Pommel
        ctx.fillPixel(x: centerX - 1, y: centerY + 10, width: 3, height: 1, color: blade, scale: scale)
    }

    // MARK: - Key pickup + HUD indicator

    private func renderKeys(
        into ctx: inout GraphicsContext, scale: CGSize,
        keys: [KeyPickup],
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        let bow = palette.lcdShade3
        let teeth = palette.lcdShade2
        let glint = palette.lcdShade0
        for k in keys {
            let bob = Int(round(sin(k.bobPhase * 3.5) * 1))
            let x = pixelOffsetX + Int(k.x)
            let y = pixelOffsetY + Int(k.y) + bob
            // 10×8 key sprite
            // Bow (ring)
            ctx.fillPixel(x: x,     y: y + 1, width: 4, height: 1, color: bow, scale: scale)
            ctx.fillPixel(x: x,     y: y + 4, width: 4, height: 1, color: bow, scale: scale)
            ctx.fillPixel(x: x,     y: y + 2, width: 1, height: 2, color: bow, scale: scale)
            ctx.fillPixel(x: x + 3, y: y + 2, width: 1, height: 2, color: bow, scale: scale)
            // Shaft
            ctx.fillPixel(x: x + 4, y: y + 2, width: 5, height: 2, color: bow, scale: scale)
            // Teeth
            ctx.fillPixel(x: x + 7, y: y + 4, width: 1, height: 2, color: teeth, scale: scale)
            ctx.fillPixel(x: x + 9, y: y + 4, width: 1, height: 2, color: teeth, scale: scale)
            // Glint
            ctx.fillPixel(x: x + 1, y: y + 2, color: glint, scale: scale)
        }
    }

    /// Tiny key icon in the HUD when the player has picked it up.
    private func renderKeyIndicator(into ctx: inout GraphicsContext, scale: CGSize) {
        let x = 60, y = 3
        let bow = palette.lcdShade0
        ctx.fillPixel(x: x,     y: y + 1, width: 4, height: 1, color: bow, scale: scale)
        ctx.fillPixel(x: x,     y: y + 4, width: 4, height: 1, color: bow, scale: scale)
        ctx.fillPixel(x: x,     y: y + 2, width: 1, height: 2, color: bow, scale: scale)
        ctx.fillPixel(x: x + 3, y: y + 2, width: 1, height: 2, color: bow, scale: scale)
        ctx.fillPixel(x: x + 4, y: y + 2, width: 5, height: 2, color: bow, scale: scale)
        ctx.fillPixel(x: x + 7, y: y + 4, width: 1, height: 2, color: bow, scale: scale)
        ctx.fillPixel(x: x + 9, y: y + 4, width: 1, height: 2, color: bow, scale: scale)
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

    // MARK: - Win screen

    private func renderWin(into ctx: inout GraphicsContext, scale: CGSize) {
        // Lighter dim than game-over (celebratory).
        ctx.fillPixel(x: 0, y: QuestKidLayout.hudHeight,
                      width: 256, height: 128,
                      color: palette.lcdShade0.opacity(0.55), scale: scale)
        // Banner with double border
        ctx.fillPixel(x: 40, y: 48, width: 176, height: 52,
                      color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: 40, y: 48, width: 176, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: 40, y: 99, width: 176, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: 40, y: 50, width: 176, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: 40, y: 97, width: 176, height: 1,
                      color: palette.lcdShade3, scale: scale)

        ctx.draw(
            Text("QUEST COMPLETE")
                .font(.system(size: 14 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 64 * scale.height),
            anchor: .center
        )

        // Hearts remaining stat
        let fullHearts = state.player.hp / 2
        let halfHeart = state.player.hp % 2 == 1
        let statText = "HEARTS: \(fullHearts)\(halfHeart ? ".5" : "")/3"
        ctx.draw(
            Text(statText)
                .font(.system(size: 9 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 80 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text("A: RETRY   MENU: LIBRARY")
                .font(.system(size: 8 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 92 * scale.height),
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
