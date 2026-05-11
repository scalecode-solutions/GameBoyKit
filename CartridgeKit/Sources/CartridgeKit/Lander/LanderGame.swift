import SwiftUI
import GameBoyKit
import ConsoleKit

/// The Lander gameplay view. Hosts a `LanderState` model, drives a
/// 60Hz physics tick while in `.playing`, and renders title /
/// mode-select / play / result screens into a `PixelCanvas`.
///
/// Controls (Classic mode):
/// - A held / D-pad ↑: main thrust (vertical lift)
/// - D-pad ←/→: lateral thrust
/// - START: pause during play; on result screens, returns to mode select
/// - A on title: open mode select
/// - A on mode select: confirm highlighted mode
/// - A on landed/crashed: retry the same mode
/// - A on pause: resume
public struct LanderGame: View {

    public let input: GameBoyInput
    @State private var state: LanderState
    @State private var resetCounter: Int = 0   // bumps when we want to restart the tick task
    @State private var animTick: Int = 0       // 60Hz counter for flame/star anims
    @Environment(\.gameBoyPalette) private var palette
    @Environment(\.gameBoyPowerOn) private var powerOn

    public init(input: GameBoyInput) {
        self.input = input
        _state = State(initialValue: LanderState())
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
            guard powerOn, state.phase == .modeSelect, let dir else { return }
            if dir.isUp        { state.moveModeSelectCursor(-1) }
            else if dir.isDown { state.moveModeSelectCursor( 1) }
        }
        .task(id: "\(resetCounter)-\(powerOn)") {
            guard powerOn else { return }
            await runTickLoop()
        }
    }

    // MARK: - Input handlers (edge-triggered)

    private func handleAPress() {
        switch state.phase {
        case .title:
            state.openModeSelect()
        case .modeSelect:
            state.confirmModeSelection()
            resetCounter &+= 1     // ensure the physics loop is freshly started
        case .paused:
            state.togglePause()
        case .landed, .crashed:
            state.retryRun()
            resetCounter &+= 1
        case .playing:
            // A is held for thrust; the rising edge isn't useful by itself.
            break
        }
    }

    private func handleStartPress() {
        switch state.phase {
        case .playing:
            state.togglePause()
        case .paused:
            state.togglePause()
        case .landed, .crashed:
            state.exitToModeSelect()
        case .title, .modeSelect:
            break
        }
    }

    // MARK: - Tick loop (60Hz physics)

    private func runTickLoop() async {
        let dt: Duration = .milliseconds(16)   // ~60Hz
        while !Task.isCancelled {
            try? await Task.sleep(for: dt)
            if Task.isCancelled { return }
            animTick &+= 1

            // Only step physics when actively playing.
            guard state.phase == .playing else { continue }

            // Sample held inputs.
            let mainHeld = input.aPressed || (input.dpad?.isUp ?? false)
            let lateral: Int = {
                if input.dpad?.isLeft  == true { return -1 }
                if input.dpad?.isRight == true { return  1 }
                return 0
            }()
            state.applyInput(mainThrust: mainHeld, lateral: lateral)
            state.tick()
        }
    }

    // MARK: - Top-level render dispatch

    private func render(into ctx: inout GraphicsContext, scale: CGSize) {
        // Always paint background first.
        ctx.fillPixel(x: 0, y: 0,
                      width: LanderState.lcdWidth,
                      height: LanderState.lcdHeight,
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
            renderCenteredBanner(into: &ctx, scale: scale,
                                 title: "PAUSED",
                                 subtitle: "A: RESUME")
        case .landed:
            renderScene(into: &ctx, scale: scale)
            renderResultBanner(into: &ctx, scale: scale,
                               title: "TOUCHDOWN",
                               subtitle: "SCORE \(state.score)",
                               hint: "A: RETRY  START: MENU")
        case .crashed:
            renderScene(into: &ctx, scale: scale)
            renderResultBanner(into: &ctx, scale: scale,
                               title: "CRASHED",
                               subtitle: String(format: "IMPACT %.2f", state.landingImpact),
                               hint: "A: RETRY  START: MENU")
        }
    }

    // MARK: - Title screen

    private func renderTitle(into ctx: inout GraphicsContext, scale: CGSize) {
        // Star field — fixed sprinkle so the title feels like "space".
        for star in titleStars {
            ctx.fillPixel(x: star.x, y: star.y, width: 1, height: 1,
                          color: palette.lcdShade2, scale: scale)
        }

        // Title
        ctx.draw(
            Text("LANDER")
                .font(.system(size: 28 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 52 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text("FOUR FLIGHTS")
                .font(.system(size: 11 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 76 * scale.height),
            anchor: .center
        )

        // Press-A pulse
        if (animTick / 30) % 2 == 0 {
            ctx.draw(
                Text("PRESS A")
                    .font(.system(size: 11 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 116 * scale.height),
                anchor: .center
            )
        }
    }

    // MARK: - Mode select

    private func renderModeSelect(into ctx: inout GraphicsContext, scale: CGSize) {
        // Title bar
        ctx.fillPixel(x: 0, y: 0, width: LanderState.lcdWidth, height: 16,
                      color: palette.lcdShade3, scale: scale)
        ctx.draw(
            Text("SELECT FLIGHT")
                .font(.system(size: 11 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade0),
            at: CGPoint(x: 128 * scale.width, y: 8 * scale.height),
            anchor: .center
        )

        // Single-button layout for v1: a single big "control panel"
        // button. As modes ship we'll switch this to a 2×2 grid; the
        // navigation cursor + selection logic is already in place.
        let modes = LanderState.Mode.allCases
        for (i, mode) in modes.enumerated() {
            let yTop = 32 + i * 28
            let selected = (i == state.modeSelectCursor)
            // Button background
            ctx.fillPixel(x: 32, y: yTop,
                          width: 192, height: 22,
                          color: selected ? palette.lcdShade2 : palette.lcdShade1,
                          scale: scale)
            // Button outline
            ctx.fillPixel(x: 32, y: yTop, width: 192, height: 1,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 32, y: yTop + 21, width: 192, height: 1,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 32, y: yTop, width: 1, height: 22,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: 223, y: yTop, width: 1, height: 22,
                          color: palette.lcdShade3, scale: scale)

            ctx.draw(
                Text(mode.displayName)
                    .font(.system(size: 13 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width,
                            y: CGFloat(yTop + 11) * scale.height),
                anchor: .center
            )
        }

        // Briefing strip
        let briefing = modes[state.modeSelectCursor].briefing
        ctx.fillPixel(x: 0, y: 128, width: LanderState.lcdWidth, height: 16,
                      color: palette.lcdShade1, scale: scale)
        ctx.draw(
            Text(briefing)
                .font(.system(size: 9 * scale.height,
                              weight: .semibold,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 136 * scale.height),
            anchor: .center
        )
    }

    // MARK: - Play scene

    private func renderScene(into ctx: inout GraphicsContext, scale: CGSize) {
        // Star field background
        for star in sceneStars {
            ctx.fillPixel(x: star.x, y: star.y, width: 1, height: 1,
                          color: palette.lcdShade1, scale: scale)
        }

        // Alignment beam: when the *landing element* (ship in Classic,
        // cargo in Pendulum) is horizontally over the pad, draw a
        // faint vertical column up from the pad surface to the HUD
        // baseline. Communicates "you're lined up, now just slow
        // down" without overwhelming the screen.
        let alignTargetX: Double = (state.mode == .pendulum) ? state.cargoX : state.shipX
        let aligned = alignTargetX >= Double(LanderState.padLeft)
                   && alignTargetX <= Double(LanderState.padRight)
        if aligned {
            let beamX = LanderState.padLeft
            let beamW = LanderState.padWidth
            let beamY = LanderState.hudHeight
            let beamH = LanderState.padTop - LanderState.hudHeight
            ctx.fillPixel(x: beamX, y: beamY,
                          width: beamW, height: beamH,
                          color: palette.lcdShade1.opacity(0.45),
                          scale: scale)
        }

        // Ground
        ctx.fillPixel(x: 0, y: LanderState.groundY,
                      width: LanderState.lcdWidth,
                      height: LanderState.lcdHeight - LanderState.groundY,
                      color: palette.lcdShade2, scale: scale)
        // Ground top-edge highlight
        ctx.fillPixel(x: 0, y: LanderState.groundY,
                      width: LanderState.lcdWidth, height: 1,
                      color: palette.lcdShade3, scale: scale)

        // Pad legs (vertical posts under the pad surface)
        ctx.fillPixel(x: LanderState.padLeft + 2, y: LanderState.padTop + 2,
                      width: 2, height: LanderState.groundY - (LanderState.padTop + 2),
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: LanderState.padRight - 4, y: LanderState.padTop + 2,
                      width: 2, height: LanderState.groundY - (LanderState.padTop + 2),
                      color: palette.lcdShade3, scale: scale)

        // Pad surface (slightly raised platform). When the ship is
        // aligned over the pad, brighten the markings into a 2px
        // band — reinforces the alignment cue at the pad itself.
        ctx.fillPixel(x: LanderState.padLeft, y: LanderState.padTop,
                      width: LanderState.padWidth, height: 2,
                      color: palette.lcdShade3, scale: scale)
        let markY = aligned ? LanderState.padTop - 2 : LanderState.padTop - 1
        let markH = aligned ? 2 : 1
        for dx in stride(from: 2, to: LanderState.padWidth - 2, by: 4) {
            ctx.fillPixel(x: LanderState.padLeft + dx,
                          y: markY,
                          width: 2, height: markH,
                          color: palette.lcdShade3, scale: scale)
        }

        // Pendulum tether + cargo — drawn before the ship so the ship
        // sprite sits ON TOP of the tether attachment point (cleaner
        // look at the hook).
        if state.mode == .pendulum {
            drawTetherAndCargo(into: &ctx, scale: scale)
        }

        // Ship
        drawShip(into: &ctx, scale: scale)

        // HUD overlay (drawn last so it's on top)
        drawHUD(into: &ctx, scale: scale)
    }

    /// Draws the tether (1px line from ship's belly to cargo's top)
    /// and the cargo crate. Skips rendering if the tether has snapped
    /// — that case ends the run on the same frame anyway, so the
    /// result banner will be on top by next render.
    private func drawTetherAndCargo(into ctx: inout GraphicsContext, scale: CGSize) {
        guard !state.tetherSnapped else { return }

        let sx = Int(state.shipX.rounded())
        let sy = Int(state.shipY.rounded())
        let cx = Int(state.cargoX.rounded())
        let cy = Int(state.cargoY.rounded())

        // Tether — Bresenham-ish line, drawn in shade2 so it reads as
        // a darker thread against the sky but stays visually quieter
        // than the ship body.
        drawLine(into: &ctx, scale: scale,
                 x0: sx, y0: sy + 5,
                 x1: cx, y1: cy - Int(LanderState.cargoHalfH),
                 color: palette.lcdShade2)

        // Cargo crate — small square outline + interior cross-hatch
        // to read as a crate even at 6x6 pixels.
        let half = Int(LanderState.cargoHalfW)
        ctx.fillPixel(x: cx - half, y: cy - half,
                      width: half * 2, height: half * 2,
                      color: palette.lcdShade3, scale: scale)
        // Crate "X" detail — a single diagonal pixel in the center
        // so the crate isn't just a solid block.
        ctx.fillPixel(x: cx, y: cy, width: 1, height: 1,
                      color: palette.lcdShade1, scale: scale)
    }

    /// Tiny line draw via Bresenham — sufficient for a short tether at
    /// our 256×144 scale. Drawn in single-pixel cells via fillPixel so
    /// it matches the rest of the canvas style.
    private func drawLine(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        x0: Int, y0: Int,
        x1: Int, y1: Int,
        color: Color
    ) {
        var x0 = x0, y0 = y0
        let dx =  abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            ctx.fillPixel(x: x0, y: y0, width: 1, height: 1, color: color, scale: scale)
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

    private func drawShip(into ctx: inout GraphicsContext, scale: CGSize) {
        let sx = Int(state.shipX.rounded())
        let sy = Int(state.shipY.rounded())

        // Flame underneath when main-thrusting (2-frame anim)
        if state.thrustingMain {
            let flameFrame = (animTick / 3) % 2
            let flameH = flameFrame == 0 ? 5 : 4
            ctx.fillPixel(x: sx - 2, y: sy + 6, width: 4, height: flameH,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: sx - 1, y: sy + 6, width: 2, height: flameH + 1,
                          color: palette.lcdShade2, scale: scale)
        }
        // Side-thrust puff
        if state.thrustingLateral != 0 {
            let side = state.thrustingLateral
            // Flame puffs OPPOSITE to motion direction
            let fx = sx + (side > 0 ? -6 : 4)
            ctx.fillPixel(x: fx, y: sy - 1, width: 2, height: 3,
                          color: palette.lcdShade2, scale: scale)
        }

        // Body — a small lander silhouette in shade3 with shade1 cockpit dot
        // Cone top
        ctx.fillPixel(x: sx - 1, y: sy - 6, width: 2, height: 2,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: sx - 2, y: sy - 4, width: 4, height: 1,
                      color: palette.lcdShade3, scale: scale)
        // Body
        ctx.fillPixel(x: sx - 3, y: sy - 3, width: 6, height: 6,
                      color: palette.lcdShade3, scale: scale)
        // Cockpit window
        ctx.fillPixel(x: sx - 1, y: sy - 1, width: 2, height: 2,
                      color: palette.lcdShade1, scale: scale)
        // Legs
        ctx.fillPixel(x: sx - 5, y: sy + 3, width: 2, height: 3,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: sx + 3, y: sy + 3, width: 2, height: 3,
                      color: palette.lcdShade3, scale: scale)
        // Foot pads
        ctx.fillPixel(x: sx - 6, y: sy + 5, width: 4, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: sx + 2, y: sy + 5, width: 4, height: 1,
                      color: palette.lcdShade3, scale: scale)
    }

    private func drawHUD(into ctx: inout GraphicsContext, scale: CGSize) {
        // HUD background strip
        ctx.fillPixel(x: 0, y: 0,
                      width: LanderState.lcdWidth,
                      height: LanderState.hudHeight,
                      color: palette.lcdShade1, scale: scale)
        ctx.fillPixel(x: 0, y: LanderState.hudHeight - 1,
                      width: LanderState.lcdWidth, height: 1,
                      color: palette.lcdShade3, scale: scale)

        // Fuel label + bar (left side)
        ctx.draw(
            Text("FUEL")
                .font(.system(size: 9 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 4 * scale.width, y: 9 * scale.height),
            anchor: .leading
        )
        // Bar outline
        let barX = 36, barY = 5, barW = 100, barH = 8
        ctx.fillPixel(x: barX, y: barY, width: barW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: barX, y: barY + barH - 1, width: barW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: barX, y: barY, width: 1, height: barH,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: barX + barW - 1, y: barY, width: 1, height: barH,
                      color: palette.lcdShade3, scale: scale)
        // Fuel fill
        let fillW = Int((Double(barW - 2) * state.fuel / 100.0).rounded())
        if fillW > 0 {
            ctx.fillPixel(x: barX + 1, y: barY + 1,
                          width: fillW, height: barH - 2,
                          color: palette.lcdShade3, scale: scale)
        }

        // VY readout (right side) — shows descent speed. When the
        // player exceeds the safe-landing threshold the readout
        // flashes between shade3 and shade1 (8-frame strobe) so the
        // "going too fast" message is visceral, not subtle.
        let vyDisp = String(format: "VY %+.2f", state.vy)
        let unsafe = abs(state.vy) > state.landingMaxVY
        let vyColor: Color = {
            if !unsafe { return palette.lcdShade2 }
            return ((animTick / 8) % 2 == 0) ? palette.lcdShade3 : palette.lcdShade1
        }()
        ctx.draw(
            Text(vyDisp)
                .font(.system(size: 9 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(vyColor),
            at: CGPoint(x: 252 * scale.width, y: 9 * scale.height),
            anchor: .trailing
        )

        // SAFE indicator — lights up in the HUD's center slot when both
        // velocity components are within landing thresholds, independent
        // of whether the ship is over the pad. Real-time skill feedback:
        // "right now you could land softly if you touched down."
        if state.landingWouldBeSafe {
            let badgeX = 144, badgeY = 4, badgeW = 36, badgeH = 10
            ctx.fillPixel(x: badgeX, y: badgeY, width: badgeW, height: badgeH,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: badgeX + 1, y: badgeY + 1,
                          width: badgeW - 2, height: badgeH - 2,
                          color: palette.lcdShade1, scale: scale)
            ctx.draw(
                Text("SAFE")
                    .font(.system(size: 8 * scale.height,
                                  weight: .black,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: CGFloat(badgeX + badgeW / 2) * scale.width,
                            y: CGFloat(badgeY + badgeH / 2) * scale.height),
                anchor: .center
            )
        }
    }

    // MARK: - Banners

    private func renderCenteredBanner(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        title: String,
        subtitle: String
    ) {
        let boxX = 56, boxY = 56, boxW = 144, boxH = 36
        // Translucent dimmer on top of the play area
        ctx.fillPixel(x: 0, y: LanderState.hudHeight,
                      width: LanderState.lcdWidth,
                      height: LanderState.lcdHeight - LanderState.hudHeight,
                      color: palette.lcdShade3.opacity(0.45), scale: scale)
        // Banner box
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: boxH,
                      color: palette.lcdShade0, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)
        ctx.fillPixel(x: boxX, y: boxY + boxH - 1, width: boxW, height: 1,
                      color: palette.lcdShade3, scale: scale)

        ctx.draw(
            Text(title)
                .font(.system(size: 14 * scale.height,
                              weight: .black,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 70 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text(subtitle)
                .font(.system(size: 9 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 84 * scale.height),
            anchor: .center
        )
    }

    private func renderResultBanner(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        title: String,
        subtitle: String,
        hint: String
    ) {
        let boxX = 40, boxY = 48, boxW = 176, boxH = 56
        ctx.fillPixel(x: 0, y: LanderState.hudHeight,
                      width: LanderState.lcdWidth,
                      height: LanderState.lcdHeight - LanderState.hudHeight,
                      color: palette.lcdShade3.opacity(0.45), scale: scale)
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
            at: CGPoint(x: 128 * scale.width, y: 64 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text(subtitle)
                .font(.system(size: 11 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade3),
            at: CGPoint(x: 128 * scale.width, y: 80 * scale.height),
            anchor: .center
        )
        ctx.draw(
            Text(hint)
                .font(.system(size: 9 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(palette.lcdShade2),
            at: CGPoint(x: 128 * scale.width, y: 95 * scale.height),
            anchor: .center
        )
    }

    // MARK: - Static star sprinkles

    /// Fixed star pattern for the title screen.
    private let titleStars: [(x: Int, y: Int)] = [
        (12, 14), (22, 30), (40, 18), (66, 42), (90, 12), (108, 36),
        (140, 22), (172, 8), (192, 28), (212, 20), (230, 40), (246, 16),
        (18, 96), (44, 110), (74, 122), (96, 100), (122, 116), (154, 108),
        (182, 124), (208, 102), (234, 118)
    ]

    /// Fixed star pattern visible during play (sparser, above ground).
    private let sceneStars: [(x: Int, y: Int)] = [
        (16, 30), (38, 44), (62, 26), (88, 50), (110, 38), (138, 28),
        (168, 46), (192, 30), (216, 40), (240, 26), (28, 70), (54, 84),
        (76, 60), (102, 78), (134, 66), (158, 86), (188, 72), (220, 60),
        (246, 84)
    ]
}

// MARK: - Built-in cartridge factory

public extension GameBoyCartridge {
    /// Built-in Lander cartridge. Multi-mode physics game — Classic
    /// mode ships in v1; additional flights (Pendulum, Mail Run, Cave
    /// Dive) plug in via the mode-select grid as they're built.
    static let lander = GameBoyCartridge(
        id: "lander",
        title: "LANDER",
        blurb: "LAND SOFT. DON'T CRASH.",
        make: { input in LanderGame(input: input) }
    )
}
