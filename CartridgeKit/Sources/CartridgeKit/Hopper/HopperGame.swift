import SwiftUI
import GameBoyKit
import ConsoleKit

/// The Hopper gameplay view. Hosts a `HopperState` model, drives a
/// 60Hz tick while in `.playing`, and renders title / mode-select /
/// play / result screens into a `PixelCanvas`.
///
/// Controls (Classic mode):
/// - D-pad: hop one cell (edge-triggered — tap to hop, hold doesn't
///   chain hops; release + re-press for a second hop)
/// - START: pause during play; on result screens, returns to mode select
/// - A on title: open mode select
/// - A on mode select: confirm highlighted mode
/// - A on won/dead: retry
/// - A on pause: resume
public struct HopperGame: View {

    public let input: GameBoyInput
    @State private var state: HopperState
    @State private var resetCounter: Int = 0
    @State private var animTick: Int = 0
    @State private var lastDpad: DPadDirection? = nil
    @Environment(\.gameBoyPalette) private var palette
    @Environment(\.gameBoyPowerOn) private var powerOn

    public init(input: GameBoyInput) {
        self.input = input
        _state = State(initialValue: HopperState())
    }

    public var body: some View {
        PixelCanvas { ctx, scale in
            render(into: &ctx, scale: scale)
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard powerOn, pressed else { return }
            handleAPress()
        }
        .onChange(of: input.startPressed) { _, pressed in
            guard powerOn, pressed else { return }
            handleStartPress()
        }
        .onChange(of: input.dpad) { _, dir in
            guard powerOn else { return }
            // Rising-edge: only fire when the previous frame had no
            // direction held. Holding the stick doesn't chain hops;
            // the player must release and re-press.
            defer { lastDpad = dir }
            guard let dir, lastDpad == nil else { return }
            handleDpad(dir)
        }
        .task(id: "\(resetCounter)-\(powerOn)") {
            guard powerOn else { return }
            await runTickLoop()
        }
    }

    // MARK: - Input handlers

    private func handleAPress() {
        switch state.phase {
        case .title:
            state.openModeSelect()
        case .modeSelect:
            state.confirmModeSelection()
            resetCounter &+= 1
        case .paused:
            state.togglePause()
        case .won, .dead:
            state.retryRun()
            resetCounter &+= 1
        case .playing:
            break
        }
    }

    private func handleStartPress() {
        switch state.phase {
        case .playing, .paused:
            state.togglePause()
        case .won, .dead:
            state.exitToModeSelect()
        case .title, .modeSelect:
            break
        }
    }

    private func handleDpad(_ dir: DPadDirection) {
        if state.phase == .modeSelect {
            if dir.isUp        { state.moveModeSelectCursor(-1) }
            else if dir.isDown { state.moveModeSelectCursor( 1) }
            return
        }
        guard state.phase == .playing else { return }
        // Cardinal hop direction. Diagonals collapse to vertical
        // (forward progress takes precedence over sidestepping).
        let hop: HopperState.HopDirection? = {
            if dir.isUp    { return .up }
            if dir.isDown  { return .down }
            if dir.isLeft  { return .left }
            if dir.isRight { return .right }
            return nil
        }()
        if let hop { state.hop(hop) }
    }

    // MARK: - Tick loop (60Hz)

    private func runTickLoop() async {
        let dt: Duration = .milliseconds(16)
        while !Task.isCancelled {
            try? await Task.sleep(for: dt)
            if Task.isCancelled { return }
            animTick &+= 1
            guard state.phase == .playing else { continue }
            state.tick()
        }
    }

    // MARK: - Top-level render dispatch

    private func render(into ctx: inout GraphicsContext, scale: CGSize) {
        ctx.fillPixel(x: 0, y: 0,
                      width: HopperState.cols * HopperState.cellSize,
                      height: HopperState.rows * HopperState.cellSize,
                      color: palette.lcdShade0, scale: scale)

        switch state.phase {
        case .title:
            renderTitle(into: &ctx, scale: scale)
        case .modeSelect:
            renderModeSelect(into: &ctx, scale: scale)
        case .playing:
            renderScene(into: &ctx, scale: scale)
        case .paused:
            renderScene(into: &ctx, scale: scale)
            renderBanner(into: &ctx, scale: scale,
                         title: "PAUSED",
                         subtitle: "A: RESUME")
        case .won:
            renderScene(into: &ctx, scale: scale)
            renderBanner(into: &ctx, scale: scale,
                         title: "SAFE!",
                         subtitle: "SCORE \(state.score)",
                         hint: "A: RETRY  START: MENU")
        case .dead:
            renderScene(into: &ctx, scale: scale)
            renderBanner(into: &ctx, scale: scale,
                         title: "GAME OVER",
                         subtitle: deathSubtitle(),
                         hint: "A: RETRY  START: MENU")
        }
    }

    private func deathSubtitle() -> String {
        switch state.lastDeath {
        case .crushed:    return "CRUSHED"
        case .drowned:    return "DROWNED"
        case .carriedOff: return "SWEPT AWAY"
        case .timeUp:     return "TIME'S UP"
        case .fellBehind: return "LEFT BEHIND"
        case .none:       return "SCORE \(state.score)"
        }
    }

    // MARK: - Title

    private func renderTitle(into ctx: inout GraphicsContext, scale: CGSize) {
        let w = HopperState.cols * HopperState.cellSize
        ctx.draw(
            Text("HOPPER")
                .font(.system(size: 28 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: CGFloat(w / 2) * scale.width, y: 52 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text("FOUR CROSSINGS")
                .font(.system(size: 11 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: CGFloat(w / 2) * scale.width, y: 76 * scale.height),
            anchor: .center
        )
        if (animTick / 30) % 2 == 0 {
            ctx.draw(
                Text("PRESS A")
                    .font(.system(size: 11 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: CGFloat(w / 2) * scale.width, y: 116 * scale.height),
                anchor: .center
            )
        }
    }

    // MARK: - Mode select

    private func renderModeSelect(into ctx: inout GraphicsContext, scale: CGSize) {
        let w = HopperState.cols * HopperState.cellSize
        // Title bar
        ctx.fillPixel(x: 0, y: 0, width: w, height: 16,
                      color: palette.lcdShade3, scale: scale)
        ctx.draw(
            Text("SELECT CROSSING")
                .font(.system(size: 11 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade0),
            at: CGPoint(x: CGFloat(w / 2) * scale.width, y: 8 * scale.height),
            anchor: .center
        )

        let modes = HopperState.Mode.allCases
        let rowHeight = 22
        let rowGap = 4
        let rowStartY = 26
        for (i, mode) in modes.enumerated() {
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
                Text(mode.displayName)
                    .font(.system(size: 12 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: CGFloat(w / 2) * scale.width,
                            y: CGFloat(yTop + rowHeight / 2) * scale.height),
                anchor: .center
            )
        }

        let briefing = modes[state.modeSelectCursor].briefing
        ctx.fillPixel(x: 0, y: 128, width: w, height: 16,
                      color: palette.lcdShade1, scale: scale)
        ctx.draw(
            Text(briefing)
                .font(.system(size: 9 * scale.height,
                              weight: .semibold,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: CGFloat(w / 2) * scale.width, y: 136 * scale.height),
            anchor: .center
        )
    }

    // MARK: - Play scene

    /// Camera pixel offset for the current mode. Zero in Classic
    /// (no scrolling); accumulates as the camera scrolls upward in
    /// Endless. Subtracted from world-pixel-Y to get screen-Y.
    private var cameraPixelOffset: Int {
        Int((state.cameraRow * Double(HopperState.cellSize)).rounded())
    }

    private func renderScene(into ctx: inout GraphicsContext, scale: CGSize) {
        switch state.mode {
        case .classic:
            drawBackground(into: &ctx, scale: scale)
            drawLanes(into: &ctx, scale: scale, camY: 0)
            drawFrog(into: &ctx, scale: scale, camY: 0)
        case .endless:
            let camY = cameraPixelOffset
            drawEndlessBackground(into: &ctx, scale: scale, camY: camY)
            drawLanes(into: &ctx, scale: scale, camY: camY)
            drawFrog(into: &ctx, scale: scale, camY: camY)
        }
        drawHUD(into: &ctx, scale: scale)
    }

    /// Paint the static terrain (water + median + road tarmac + start
    /// sidewalk + goal row's grassy bank). Hazards are drawn on top.
    private func drawBackground(into ctx: inout GraphicsContext, scale: CGSize) {
        let cs = HopperState.cellSize

        // Goal row (top): grassy bank. Decorate with 4 lily-pad-style
        // tiles at fixed positions so the destination reads as "land."
        let goalY = HopperState.goalRow * cs
        ctx.fillPixel(x: 0, y: goalY,
                      width: HopperState.cols * cs, height: cs,
                      color: palette.lcdShade2, scale: scale)
        // Lily pad tiles — purely decorative in v1 (entire goal row wins).
        let padCols = [4, 12, 20, 27]
        for col in padCols {
            let x = col * cs
            ctx.fillPixel(x: x + 1, y: goalY + 1, width: cs - 2, height: cs - 2,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + 2, y: goalY + 2, width: cs - 4, height: cs - 4,
                          color: palette.lcdShade1, scale: scale)
        }

        // Water region (rows between goal and median, excluding the
        // first water buffer row directly below the goal).
        let waterStart = (HopperState.goalRow + 1) * cs
        let waterEnd   = HopperState.medianRow * cs
        ctx.fillPixel(x: 0, y: waterStart,
                      width: HopperState.cols * cs,
                      height: waterEnd - waterStart,
                      color: palette.lcdShade1, scale: scale)
        // Water sparkle dots — every 4 cells in a staggered pattern.
        for row in (HopperState.goalRow + 1)..<HopperState.medianRow {
            let yoff = row * cs + (row % 2 == 0 ? 2 : 5)
            for col in stride(from: row % 2 == 0 ? 1 : 3, to: HopperState.cols, by: 4) {
                ctx.fillPixel(x: col * cs + 3, y: yoff, width: 1, height: 1,
                              color: palette.lcdShade2, scale: scale)
            }
        }

        // Median row.
        let medianY = HopperState.medianRow * cs
        ctx.fillPixel(x: 0, y: medianY,
                      width: HopperState.cols * cs, height: cs,
                      color: palette.lcdShade2, scale: scale)
        // Grass tufts for texture
        for col in stride(from: 1, to: HopperState.cols, by: 3) {
            ctx.fillPixel(x: col * cs + 2, y: medianY + 1, width: 1, height: 2,
                          color: palette.lcdShade3, scale: scale)
        }

        // Road tarmac (rows median+1 through 12).
        let roadStart = (HopperState.medianRow + 1) * cs
        let roadEnd   = 13 * cs
        ctx.fillPixel(x: 0, y: roadStart,
                      width: HopperState.cols * cs,
                      height: roadEnd - roadStart,
                      color: palette.lcdShade0, scale: scale)
        // Road lane stripes — small dashed line down each lane center.
        for row in (HopperState.medianRow + 1)..<13 {
            let stripeY = row * cs + cs - 1
            for col in stride(from: 0, to: HopperState.cols, by: 4) {
                ctx.fillPixel(x: col * cs + 1, y: stripeY, width: 2, height: 1,
                              color: palette.lcdShade2, scale: scale)
            }
        }

        // Bottom sidewalk / start area (rows 13..<rows).
        let walkStart = 13 * cs
        ctx.fillPixel(x: 0, y: walkStart,
                      width: HopperState.cols * cs,
                      height: HopperState.rows * cs - walkStart,
                      color: palette.lcdShade2, scale: scale)
        // Crosshatch pattern on sidewalk
        for row in 13..<HopperState.rows {
            for col in 0..<HopperState.cols where (col + row) % 2 == 0 {
                ctx.fillPixel(x: col * cs + 3, y: row * cs + 3,
                              width: 2, height: 2,
                              color: palette.lcdShade1, scale: scale)
            }
        }
    }

    /// Paint terrain for Endless mode: every visible world row gets
    /// painted as its lane's kind (river / road / safe grass). The
    /// camera offset is applied per-row so scrolling is smooth.
    private func drawEndlessBackground(
        into ctx: inout GraphicsContext, scale: CGSize, camY: Int
    ) {
        let cs = HopperState.cellSize
        let totalW = HopperState.cols * cs
        let viewportH = HopperState.rows * cs

        // For every screen row, figure out which world row it
        // corresponds to, look up the lane, and paint that row's
        // terrain. Faster than iterating every lane in the array.
        for screenRow in 0..<HopperState.rows {
            let worldRow = screenRow + Int((state.cameraRow).rounded())
            // Lane lookup — O(lanes) but lanes are small.
            let laneIdx = state.lanes.firstIndex(where: { $0.row == worldRow })
            let kind: HopperState.LaneKind = laneIdx.map { state.lanes[$0].kind } ?? .safe
            let yTop = screenRow * cs - (camY - Int(state.cameraRow.rounded()) * cs)
            // (`camY - cameraRow*cs` is the fractional pixel
            // offset — non-zero only mid-tick. Subtracting it gives
            // sub-cell smoothness.)
            paintEndlessRow(into: &ctx, scale: scale,
                            kind: kind, worldRow: worldRow,
                            x: 0, y: yTop, w: totalW, h: cs)
        }
        _ = viewportH
    }

    /// Paint a single row of Endless terrain.
    private func paintEndlessRow(
        into ctx: inout GraphicsContext, scale: CGSize,
        kind: HopperState.LaneKind,
        worldRow: Int,
        x: Int, y: Int, w: Int, h: Int
    ) {
        switch kind {
        case .safe:
            // Grass strip.
            ctx.fillPixel(x: x, y: y, width: w, height: h,
                          color: palette.lcdShade2, scale: scale)
            // Tufts — sparser than median grass to differentiate.
            // Use worldRow to deterministically place them (no per-
            // frame jitter).
            let pattern = abs(worldRow * 7919) & 0x3
            for col in stride(from: pattern + 1, to: HopperState.cols, by: 3) {
                ctx.fillPixel(x: x + col * HopperState.cellSize + 2, y: y + 1,
                              width: 1, height: 2,
                              color: palette.lcdShade3, scale: scale)
            }
        case .road:
            // Tarmac with a faint dashed centerline.
            ctx.fillPixel(x: x, y: y, width: w, height: h,
                          color: palette.lcdShade0, scale: scale)
            let stripeY = y + h - 1
            for col in stride(from: 0, to: HopperState.cols, by: 4) {
                ctx.fillPixel(x: x + col * HopperState.cellSize + 1,
                              y: stripeY, width: 2, height: 1,
                              color: palette.lcdShade2, scale: scale)
            }
        case .river:
            ctx.fillPixel(x: x, y: y, width: w, height: h,
                          color: palette.lcdShade1, scale: scale)
            // Sparkles — pattern depends on worldRow to avoid moving
            // with the camera (they stay attached to the water row).
            let stagger = (worldRow & 1) == 0
            for col in stride(from: stagger ? 1 : 3, to: HopperState.cols, by: 4) {
                ctx.fillPixel(x: x + col * HopperState.cellSize + 3,
                              y: y + (stagger ? 2 : 5),
                              width: 1, height: 1,
                              color: palette.lcdShade2, scale: scale)
            }
        }
    }

    /// Draw all hazard entities (cars + logs) at their current
    /// continuous-X positions. `camY` is subtracted from each lane's
    /// world-Y so Endless mode scrolls smoothly; pass 0 in Classic.
    private func drawLanes(into ctx: inout GraphicsContext, scale: CGSize, camY: Int) {
        let cs = HopperState.cellSize
        let viewportH = HopperState.rows * cs
        for (li, lane) in state.lanes.enumerated() {
            let y = lane.row * cs - camY
            // Cull lanes entirely above/below the viewport.
            if y + cs < 0 || y > viewportH { continue }
            for entity in state.entities[li] {
                let px = Int((entity.x * Double(cs)).rounded())
                let pw = lane.entityWidth * cs
                drawEntity(into: &ctx, scale: scale,
                           kind: lane.kind,
                           direction: lane.direction,
                           variant: lane.visualVariant,
                           x: px, y: y, w: pw, h: cs)
            }
        }
    }

    private func drawEntity(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        kind: HopperState.LaneKind,
        direction: HopperState.LaneDirection,
        variant: Int,
        x: Int, y: Int, w: Int, h: Int
    ) {
        switch kind {
        case .safe:
            // Safe lanes have no entities (entityCount == 0); this
            // branch is unreachable in practice but keeps the switch
            // exhaustive.
            return
        case .road:
            // Car silhouette — body + windshield strip + a 2px wheels
            // line. Variants tweak shape so adjacent lanes don't look
            // identical.
            let bodyTop = y + 1
            let bodyH   = h - 3
            ctx.fillPixel(x: x, y: bodyTop, width: w, height: bodyH,
                          color: palette.lcdShade3, scale: scale)
            // Windshield (lighter band)
            let winX = (direction == .right) ? x + 1 : x + w - 4
            ctx.fillPixel(x: winX, y: bodyTop + 1, width: 3, height: 2,
                          color: palette.lcdShade1, scale: scale)
            // Wheels (variant 2 has 3 axles for "truck")
            let wheelY = bodyTop + bodyH
            let wheelCount = (variant == 2) ? 3 : 2
            for i in 0..<wheelCount {
                let wx = x + 1 + i * ((w - 3) / max(1, wheelCount - 1))
                ctx.fillPixel(x: wx, y: wheelY, width: 2, height: 1,
                              color: palette.lcdShade3, scale: scale)
            }
        case .river:
            // Log: long brown block with end-cap rings.
            ctx.fillPixel(x: x, y: y + 1, width: w, height: h - 2,
                          color: palette.lcdShade3, scale: scale)
            // Inner highlight
            ctx.fillPixel(x: x + 1, y: y + 2, width: w - 2, height: h - 4,
                          color: palette.lcdShade2, scale: scale)
            // End caps — small rings on each end
            ctx.fillPixel(x: x, y: y + 1, width: 2, height: h - 2,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: x + w - 2, y: y + 1, width: 2, height: h - 2,
                          color: palette.lcdShade3, scale: scale)
            // Surface stripes
            for stripe in stride(from: 3, to: w - 3, by: 4) {
                ctx.fillPixel(x: x + stripe, y: y + 3, width: 1, height: h - 6,
                              color: palette.lcdShade3, scale: scale)
            }
        }
    }

    /// Frog sprite — small body + eye dots. Position uses pixelX while
    /// riding a log so it smoothly drifts; otherwise snaps to cell X.
    /// `camY` subtracts from world-Y for Endless mode scrolling.
    private func drawFrog(into ctx: inout GraphicsContext, scale: CGSize, camY: Int) {
        let cs = HopperState.cellSize
        let px = Int((state.frogPixelX * Double(cs)).rounded())
        let py = state.frogY * cs - camY
        // Body
        ctx.fillPixel(x: px + 1, y: py + 2, width: cs - 2, height: cs - 3,
                      color: palette.lcdShade3, scale: scale)
        // Inner shade for depth
        ctx.fillPixel(x: px + 2, y: py + 3, width: cs - 4, height: cs - 5,
                      color: palette.lcdShade2, scale: scale)
        // Eyes
        ctx.fillPixel(x: px + 2, y: py + 1, width: 1, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: px + cs - 3, y: py + 1, width: 1, height: 1,
                      color: palette.lcdShade3, scale: scale)
    }

    /// HUD: lives, score, time. Top 16px strip.
    private func drawHUD(into ctx: inout GraphicsContext, scale: CGSize) {
        let cs = HopperState.cellSize
        let w  = HopperState.cols * cs
        let h  = HopperState.hudRows * cs
        ctx.fillPixel(x: 0, y: 0, width: w, height: h,
                      color: palette.lcdShade1, scale: scale)
        ctx.fillPixel(x: 0, y: h - 1, width: w, height: 1,
                      color: palette.lcdShade3, scale: scale)

        // Lives (heart dots on the left)
        for i in 0..<state.lives {
            let lx = 4 + i * 8
            ctx.fillPixel(x: lx, y: 5, width: 5, height: 5,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: lx + 1, y: 6, width: 3, height: 3,
                          color: palette.lcdShade1, scale: scale)
        }

        // Score (center)
        ctx.draw(
            Text(String(format: "%04d", state.score))
                .font(.system(size: 11 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: CGFloat(w / 2) * scale.width, y: 8 * scale.height),
            anchor: .center
        )

        // Right-side readout — Classic shows TIME, Endless shows ROWS climbed.
        switch state.mode {
        case .classic:
            let seconds = max(0, state.timeRemainingTicks / 60)
            let lowTime = seconds <= 5
            let color: Color = {
                if !lowTime { return palette.lcdShade3 }
                return ((animTick / 8) % 2 == 0) ? palette.lcdShade3 : palette.lcdShade1
            }()
            ctx.draw(
                Text(String(format: "TIME %02d", seconds))
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(color),
                at: CGPoint(x: CGFloat(w - 4) * scale.width, y: 8 * scale.height),
                anchor: .trailing
            )
        case .endless:
            let climbed = max(0, HopperState.startRow - state.bestRow)
            ctx.draw(
                Text("ROWS \(climbed)")
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: CGFloat(w - 4) * scale.width, y: 8 * scale.height),
                anchor: .trailing
            )
        }
    }

    // MARK: - Banner

    private func renderBanner(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        title: String,
        subtitle: String,
        hint: String? = nil
    ) {
        let cs = HopperState.cellSize
        let w  = HopperState.cols * cs
        let hudH = HopperState.hudRows * cs
        // Dimmer
        ctx.fillPixel(x: 0, y: hudH, width: w,
                      height: HopperState.rows * cs - hudH,
                      color: palette.lcdShade3.opacity(0.45), scale: scale)
        let boxX = 40, boxW = 176
        let boxH = (hint != nil) ? 56 : 36
        let boxY = (HopperState.rows * cs - boxH) / 2 + 4
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: boxH,
                      color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY + boxH - 1, width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)

        ctx.draw(
            Text(title)
                .font(.system(size: 16 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: CGFloat(w / 2) * scale.width,
                        y: CGFloat(boxY + 16) * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text(subtitle)
                .font(.system(size: 10 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: CGFloat(w / 2) * scale.width,
                        y: CGFloat(boxY + 32) * scale.height),
            anchor: .center
        )
        if let hint {
            ctx.draw(
                Text(hint)
                    .font(.system(size: 9 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: CGFloat(w / 2) * scale.width,
                            y: CGFloat(boxY + boxH - 10) * scale.height),
                anchor: .center
            )
        }
    }
}

// MARK: - Built-in cartridge factory

public extension GameBoyCartridge {
    /// Built-in Hopper cartridge. Multi-mode road-and-river crossing
    /// game — Classic mode ships in v1; Endless, Night Shift, and
    /// Heist plug in via the mode-select grid as they're built.
    static let hopper = GameBoyCartridge(
        id: "hopper",
        title: "HOPPER",
        blurb: "HOP. DODGE. REACH THE TOP.",
        make: { input in HopperGame(input: input) }
    )
}
