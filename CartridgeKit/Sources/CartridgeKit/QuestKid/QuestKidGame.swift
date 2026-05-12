import SwiftUI
import GameBoyKit
import ConsoleKit

/// QUESTKID — a small top-down Zelda-like adventure. Hub-style
/// dungeon select on a heart-shaped map: a tutorial dungeon at the
/// center plus six letter-shape dungeons spelling S-H-E-L-B-Y.
/// Sword combat, wandering enemies, hearts HUD, per-dungeon clear
/// records, themed visuals per dungeon. Controls:
///
/// - D-pad: walk in 4 directions
/// - A:     swing sword
/// - B:     (reserved for items)
/// - START: pause menu
/// - MENU:  return to library (handled by CartridgeShelf)
public struct QuestKidGame: View {

    public let input: GameBoyInput
    @State private var state: QuestKidState
    @State private var resetCounter: Int = 0
    @State private var swingPending: Bool = false   // edge-trigger A-button
    @State private var pauseSelectedIndex: Int = 0  // 0 = resume, 1 = back to dungeons
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
                state.openDungeonSelect()
            case .dungeonSelect:
                state.enterDungeon(state.currentDungeonIndex)
                resetCounter &+= 1
            case .gameOver, .won:
                state.reset()
                resetCounter &+= 1
            case .paused:
                // 0 = resume, 1 = back to dungeons
                if pauseSelectedIndex == 0 {
                    state.closePauseMenu()
                } else {
                    state.returnToDungeonSelect()
                }
            default:
                swingPending = true
            }
        }
        // D-pad navigates non-gameplay menus.
        .onChange(of: input.dpad) { _, newValue in
            guard powerOn, let newDir = newValue else { return }
            switch state.phase {
            case .dungeonSelect:
                state.moveDungeonSelectCursor(newDir)
            case .paused:
                if newDir.isUp   { pauseSelectedIndex = max(0, pauseSelectedIndex - 1) }
                if newDir.isDown { pauseSelectedIndex = min(1, pauseSelectedIndex + 1) }
            default:
                break
            }
        }
        // B button on win/gameOver returns to dungeon-select; on
        // dungeon-select, returns to title; on pause overlay, closes it.
        .onChange(of: input.bPressed) { _, pressed in
            guard powerOn, pressed else { return }
            switch state.phase {
            case .gameOver, .won:
                state.returnToDungeonSelect()
            case .dungeonSelect:
                state.returnToTitle()
            case .paused:
                state.closePauseMenu()
            default:
                break
            }
        }
        // START button — toggles the pause overlay during play.
        .onChange(of: input.startPressed) { _, pressed in
            guard powerOn, pressed else { return }
            switch state.phase {
            case .playing:
                state.openPauseMenu()
                pauseSelectedIndex = 0
            case .paused:
                state.closePauseMenu()
            default:
                break
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

        // Title and dungeon-select short-circuit the rest of the render.
        if state.phase == .title {
            renderTitle(into: &ctx, scale: scale)
            return
        }
        if state.phase == .dungeonSelect {
            renderDungeonSelect(into: &ctx, scale: scale)
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
                   theme: state.currentDungeon.theme,
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
        } else if state.phase == .paused {
            renderPauseOverlay(into: &ctx, scale: scale)
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
        room: Room, theme: DungeonTheme,
        pixelOffsetX: Int, pixelOffsetY: Int
    ) {
        for row in 0..<QuestKidLayout.roomRows {
            for col in 0..<QuestKidLayout.roomCols {
                let tile = room.tile(col: col, row: row)
                let x = pixelOffsetX + col * QuestKidLayout.tileSize
                let y = pixelOffsetY + row * QuestKidLayout.tileSize
                drawTile(into: &ctx, scale: scale, x: x, y: y,
                         tile: tile, theme: theme, col: col, row: row)
            }
        }
    }

    private func drawTile(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int, tile: TileKind,
        theme: DungeonTheme = .ruins,
        col: Int = 0, row: Int = 0
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
            drawStoneFloor(into: &ctx, scale: scale, x: x, y: y,
                           theme: theme, col: col, row: row)

        case .wallDark:
            drawDungeonWall(into: &ctx, scale: scale, x: x, y: y,
                            theme: theme, col: col, row: row)

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

        case .secretPassage:
            // Looks almost identical to wallDark, but with a faint
            // diagonal crack — the only visual hint that this tile is
            // walkable. Players have to lean in to spot it.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: t - 2, height: t - 2, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x, y: y + 7, width: t, height: 1, color: palette.lcdShade3, scale: scale)
            // Diagonal hairline crack — 5 pixels at slight angle
            ctx.fillPixel(x: x + 3,  y: y + 4,  width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 4,  y: y + 5,  width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 5,  y: y + 6,  width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 6,  y: y + 8,  width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 7,  y: y + 9,  width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 8,  y: y + 11, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 9,  y: y + 12, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
        }
    }

    // MARK: - Themed dungeon floor + wall

    /// Theme-aware stone floor tile. Each dungeon's `DungeonTheme` gets
    /// its own base shade + accent stipple pattern, all within the
    /// 4-shade LCD palette.
    private func drawStoneFloor(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int,
        theme: DungeonTheme, col: Int, row: Int
    ) {
        let t = QuestKidLayout.tileSize
        // Deterministic per-tile "random" — same input always paints same output.
        let seed = (col &* 13) ^ (row &* 31)

        switch theme {
        case .serpentine:
            // Pale stone with a faint diagonal scale accent on every
            // other tile. Reads as a snake-skin grout.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + t - 1, y: y, width: 1, height: t, color: palette.lcdShade2, scale: scale)
            if seed & 1 == 0 {
                ctx.fillPixel(x: x + 4, y: y + 4, color: palette.lcdShade2, scale: scale)
                ctx.fillPixel(x: x + 5, y: y + 5, color: palette.lcdShade2, scale: scale)
                ctx.fillPixel(x: x + 6, y: y + 6, color: palette.lcdShade2, scale: scale)
            }

        case .caverns:
            // Wet dark stone with intermittent water drops.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x, y: y + t - 1, width: t, height: 1, color: palette.lcdShade2, scale: scale)
            // 1 in 3 tiles has a small puddle
            if seed % 3 == 0 {
                ctx.fillPixel(x: x + 5, y: y + 7, width: 4, height: 2, color: palette.lcdShade2, scale: scale)
                ctx.fillPixel(x: x + 6, y: y + 8, width: 1, height: 1, color: palette.lcdShade0, scale: scale)
            }
            if seed % 5 == 0 {
                ctx.fillPixel(x: x + 11, y: y + 12, width: 2, height: 1, color: palette.lcdShade2, scale: scale)
            }

        case .library:
            // Bright stone (parchment-toned) with subtle dust motes.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x, y: y + t - 1, width: t, height: 1, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + t - 1, y: y, width: 1, height: t, color: palette.lcdShade1, scale: scale)
            if seed % 4 == 0 {
                ctx.fillPixel(x: x + 6, y: y + 10, color: palette.lcdShade2, scale: scale)
            }

        case .boneyard:
            // Pale bone-toned floor with occasional bone-shard pixel.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade0, scale: scale)
            ctx.fillPixel(x: x, y: y + t - 1, width: t, height: 1, color: palette.lcdShade2, scale: scale)
            // 1 in 4 tiles has a bone shard fragment
            if seed % 4 == 0 {
                ctx.fillPixel(x: x + 3, y: y + 9, width: 4, height: 1, color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: x + 2, y: y + 9, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: x + 7, y: y + 9, width: 1, height: 1, color: palette.lcdShade3, scale: scale)
            }

        case .grove:
            // Mossy stone — slightly lighter overall with leaf-stipple accents.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x + t - 1, y: y, width: 1, height: t, color: palette.lcdShade2, scale: scale)
            // 1 in 3 tiles has a few leaves
            if seed % 3 == 0 {
                ctx.fillPixel(x: x + 4, y: y + 4, color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: x + 11, y: y + 11, color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: x + 7, y: y + 8, color: palette.lcdShade2, scale: scale)
            }

        case .meadow, .ruins:
            // Default — the original Phase-3 stone look. Used by the
            // tutorial vault and by Hollow Halls.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade1, scale: scale)
            ctx.fillPixel(x: x, y: y + t - 1, width: t, height: 1, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x + t - 1, y: y, width: 1, height: t, color: palette.lcdShade2, scale: scale)
        }
    }

    /// Theme-aware dungeon wall tile.
    private func drawDungeonWall(
        into ctx: inout GraphicsContext, scale: CGSize,
        x: Int, y: Int,
        theme: DungeonTheme, col: Int, row: Int
    ) {
        let t = QuestKidLayout.tileSize
        let seed = (col &* 13) ^ (row &* 31)

        switch theme {
        case .serpentine:
            // Tightly-mortared brick — many horizontal seams to evoke
            // ribs/scales.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: t - 2, height: t - 2, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x, y: y + 4,  width: t, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x, y: y + 9,  width: t, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x, y: y + 13, width: t, height: 1, color: palette.lcdShade3, scale: scale)

        case .caverns:
            // Damp cave wall — irregular dark crags.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 2, y: y + 2, width: t - 4, height: t - 4, color: palette.lcdShade2, scale: scale)
            // Cragged outline (deterministic per tile)
            ctx.fillPixel(x: x + (seed & 7), y: y + 3, width: 2, height: 1, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 10, y: y + 11, width: 3, height: 1, color: palette.lcdShade3, scale: scale)

        case .library:
            // Wall lined with stacked book spines (alternating fills).
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            // 4 vertical "books" (each 3px wide w/ 1px gap), heights alternate
            for i in 0..<4 {
                let bx = x + 1 + i * 4
                let topInset = (i % 2 == 0) ? 2 : 4
                let bottomInset = (i % 2 == 0) ? 2 : 1
                ctx.fillPixel(x: bx, y: y + topInset,
                              width: 3, height: t - topInset - bottomInset,
                              color: i % 2 == 0 ? palette.lcdShade1 : palette.lcdShade2,
                              scale: scale)
            }

        case .boneyard:
            // Crumbling wall with cracks and an occasional skull pixel.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: t - 2, height: t - 2, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x, y: y + 7, width: t, height: 1, color: palette.lcdShade3, scale: scale)
            // Cracks
            ctx.fillPixel(x: x + 3, y: y + 2,  width: 1, height: 4, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 12, y: y + 10, width: 1, height: 4, color: palette.lcdShade3, scale: scale)

        case .grove:
            // Stone wall draped in vine/leaf accents.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: t - 2, height: t - 2, color: palette.lcdShade2, scale: scale)
            // Leaf clumps on alternate tiles
            if seed & 1 == 0 {
                ctx.fillPixel(x: x + 3, y: y + 11, width: 2, height: 3, color: palette.lcdShade1, scale: scale)
                ctx.fillPixel(x: x + 2, y: y + 13, color: palette.lcdShade1, scale: scale)
            } else {
                ctx.fillPixel(x: x + 11, y: y + 2, width: 2, height: 3, color: palette.lcdShade1, scale: scale)
                ctx.fillPixel(x: x + 13, y: y + 4, color: palette.lcdShade1, scale: scale)
            }

        case .meadow, .ruins:
            // Default dark slate brick — original look.
            ctx.fillPixel(x: x, y: y, width: t, height: t, color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 1, y: y + 1, width: t - 2, height: t - 2, color: palette.lcdShade2, scale: scale)
            ctx.fillPixel(x: x, y: y + 7,  width: t, height: 1, color: palette.lcdShade3, scale: scale)
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
        let outline = palette.lcdShade3
        let fill = palette.lcdShade2
        let highlight = palette.lcdShade0
        for h in hearts {
            // Small hearts flicker out in their last 2 seconds.
            if !h.isPersistent, h.ttl < 2 {
                let phase = Int(h.ttl * 8) % 2
                if phase == 0 { continue }
            }
            let bob = Int(round(sin(h.bobPhase * 4) * 1))
            let x = pixelOffsetX + Int(h.x)
            let y = pixelOffsetY + Int(h.y) + bob

            switch h.kind {
            case .small:
                // 8×7 heart shape — drops from enemies
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
                ctx.fillPixel(x: x + 2, y: y + 2, color: highlight, scale: scale)

            case .big:
                // 12×11 chunky reward heart with a constant pulsing
                // shimmer so it reads as a power-up, not a drop.
                let bits: [[Int]] = [
                    [0,1,1,1,0,0,0,1,1,1,0,0],
                    [1,2,2,2,1,0,1,2,2,2,1,0],
                    [1,2,3,2,2,1,2,2,3,2,1,0],
                    [1,2,2,2,2,2,2,2,2,2,1,0],
                    [1,2,2,2,2,2,2,2,2,2,1,0],
                    [0,1,2,2,2,2,2,2,2,1,0,0],
                    [0,0,1,2,2,2,2,2,1,0,0,0],
                    [0,0,0,1,2,2,2,1,0,0,0,0],
                    [0,0,0,0,1,2,1,0,0,0,0,0],
                    [0,0,0,0,0,1,0,0,0,0,0,0],
                ]
                for (row, line) in bits.enumerated() {
                    for (col, v) in line.enumerated() where v != 0 {
                        let c: Color
                        switch v {
                        case 1: c = outline
                        case 2: c = fill
                        default: c = highlight
                        }
                        ctx.fillPixel(x: x + col, y: y + row, color: c, scale: scale)
                    }
                }
                // Twinkle that orbits the heart
                let twinkleAngle = h.bobPhase * 2
                let tx = Int(cos(twinkleAngle) * 5) + 6
                let ty = Int(sin(twinkleAngle) * 4) + 4
                ctx.fillPixel(x: x + tx, y: y + ty, color: highlight, scale: scale)
            }
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
            Text("DANGEROUS TO GO ALONE.")
                .font(.system(size: 8 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 64 * scale.height),
            anchor: .center
        )

        // Decorative sword glyph centered below subtitle
        renderSwordGlyph(into: &ctx, scale: scale, centerX: 128, centerY: 84)

        // Saved record line — shown only after the tutorial is cleared.
        if state.record.cleared["tutorial"] == true {
            let halfHearts = state.record.bestHearts["tutorial"] ?? 0
            let full = halfHearts / 2
            let halfStr = halfHearts % 2 == 1 ? ".5" : ""
            // Count cleared SHELBY dungeons for a progress hint.
            let totalLetterDungeons = state.dungeons.filter { $0.letter != nil }.count
            let clearedLetterDungeons = state.dungeons
                .filter { $0.letter != nil && state.record.cleared[$0.id] == true }
                .count
            let progressLine = totalLetterDungeons > 0
                ? "✓ TUTORIAL CLEARED · \(clearedLetterDungeons)/\(totalLetterDungeons) DUNGEONS"
                : "✓ TUTORIAL CLEARED · BEST: \(full)\(halfStr) HEARTS"
            ctx.draw(
                Text(progressLine)
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

    // MARK: - Dungeon select (heart-shape map of dungeons)

    private func renderDungeonSelect(into ctx: inout GraphicsContext, scale: CGSize) {
        // Background panel
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                      color: palette.lcdShade0, scale: scale)
        // Header bar
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 14,
                      color: palette.lcdShade3, scale: scale)
        ctx.draw(
            Text("SELECT QUEST")
                .font(.system(size: 10 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade0),
            at: CGPoint(x: 128 * scale.width, y: 7 * scale.height),
            anchor: .center
        )

        // Draw each dungeon's dot (subtly tracing a heart silhouette).
        for (i, dungeon) in state.dungeons.enumerated() {
            let isSelected = i == state.currentDungeonIndex
            let cleared = state.record.cleared[dungeon.id] == true
            let cx = dungeon.mapDotX
            let cy = dungeon.mapDotY

            // Soft halo for the selected dot.
            if isSelected {
                ctx.fillPixel(x: cx - 5, y: cy - 5, width: 10, height: 10,
                              color: palette.lcdShade2.opacity(0.5), scale: scale)
            }
            // The dot itself
            let dotColor: Color = cleared
                ? palette.lcdShade3
                : (isSelected ? palette.lcdShade3 : palette.lcdShade2)
            ctx.fillPixel(x: cx - 3, y: cy - 3, width: 6, height: 6,
                          color: dotColor, scale: scale)
            ctx.fillPixel(x: cx - 2, y: cy - 4, width: 4, height: 8,
                          color: dotColor, scale: scale)
            ctx.fillPixel(x: cx - 4, y: cy - 2, width: 8, height: 4,
                          color: dotColor, scale: scale)
            // Inner highlight (only when selected) — gives a pulsing feel.
            if isSelected {
                ctx.fillPixel(x: cx - 1, y: cy - 1, width: 2, height: 2,
                              color: palette.lcdShade0, scale: scale)
            }
            // Tiny ✓ next to cleared dungeons.
            if cleared {
                ctx.fillPixel(x: cx + 5, y: cy - 2, width: 1, height: 2,
                              color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: cx + 6, y: cy,     width: 1, height: 2,
                              color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: cx + 7, y: cy - 1, width: 1, height: 1,
                              color: palette.lcdShade3, scale: scale)
                ctx.fillPixel(x: cx + 8, y: cy - 3, width: 1, height: 1,
                              color: palette.lcdShade3, scale: scale)
            }
        }

        // Selected dungeon's name + letter
        let current = state.dungeons[state.currentDungeonIndex]
        ctx.draw(
            Text(current.name)
                .font(.system(size: 12 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 122 * scale.height),
            anchor: .center
        )
        if current.letter == nil {
            ctx.draw(
                Text("TUTORIAL")
                    .font(.system(size: 7 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 132 * scale.height),
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

    // MARK: - Pause overlay

    private func renderPauseOverlay(into ctx: inout GraphicsContext, scale: CGSize) {
        // Dim the playfield.
        ctx.fillPixel(x: 0, y: QuestKidLayout.hudHeight,
                      width: 256, height: 128,
                      color: palette.lcdShade3.opacity(0.55), scale: scale)
        // Panel
        let boxX = 48, boxY = 42, boxW = 160, boxH = 60
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: boxH,
                      color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY + boxH - 1, width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        // Title
        ctx.draw(
            Text("PAUSED")
                .font(.system(size: 13 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 55 * scale.height),
            anchor: .center
        )
        // Two items: RESUME (0) and BACK TO DUNGEONS (1).
        let items = ["RESUME", "BACK TO DUNGEONS"]
        for (i, label) in items.enumerated() {
            let yTop = 68 + i * 13
            let isSelected = i == pauseSelectedIndex
            if isSelected {
                ctx.fillPixel(x: 56, y: yTop - 1, width: 144, height: 11,
                              color: palette.lcdShade2, scale: scale)
                // ▶ pointer
                ctx.fillPixel(x: 60, y: yTop + 2, width: 2, height: 4,
                              color: palette.lcdShade0, scale: scale)
                ctx.fillPixel(x: 62, y: yTop + 3, width: 1, height: 2,
                              color: palette.lcdShade0, scale: scale)
            }
            ctx.draw(
                Text(label)
                    .font(.system(size: 9 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: CGFloat(yTop + 5) * scale.height),
                anchor: .center
            )
        }
        // Footer hint
        ctx.draw(
            Text("A: SELECT   B/START: RESUME")
                .font(.system(size: 7 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 110 * scale.height),
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
        let theme = state.currentDungeon.theme
        renderRoom(into: &ctx, scale: scale,
                   room: state.rooms[from],
                   theme: theme,
                   pixelOffsetX: fromOffX, pixelOffsetY: hud + fromOffY)
        renderRoom(into: &ctx, scale: scale,
                   room: state.rooms[to],
                   theme: theme,
                   pixelOffsetX: toOffX,   pixelOffsetY: hud + toOffY)
        // Player rides along with the "from" room.
        renderPlayer(into: &ctx, scale: scale,
                     pixelOffsetX: fromOffX, pixelOffsetY: hud + fromOffY)
    }
}

// MARK: - Cartridge factory

public extension GameBoyCartridge {
    /// Built-in: QUESTKID — a small top-down Zelda-like with a
    /// heart-shaped dungeon-select map and six letter-shape
    /// dungeons spelling S-H-E-L-B-Y around a central tutorial.
    ///
    /// Blurb is a deep-cut callback to the original NES Zelda's
    /// most famous cryptic hint, "EASTMOST PENNINSULA IS THE SECRET"
    /// — east/west flipped to match the SHELBY map, with the
    /// archaic Latin V-for-U spelling of ISTHMUS (a peninsula's
    /// geographic cousin) standing in for the iconic mistranslation.
    /// "MV" is hidden inside ISTH-MV-S as a brand wink.
    static let questKid = GameBoyCartridge(
        id: "questkid",
        title: "QUESTKID",
        blurb: "WESTMOST ISTHMVS IS THE SECRET.",
        make: { input in QuestKidGame(input: input) }
    )
}
