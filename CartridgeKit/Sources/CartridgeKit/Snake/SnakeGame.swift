import SwiftUI
import GameBoyKit
import ConsoleKit

/// The Snake gameplay view. Hosts a `SnakeState` model, drives ticks
/// while the model is in `.playing`, and renders the snake/food/HUD
/// into a `PixelCanvas`.
///
/// Controls:
/// - D-pad: turn (reversing into yourself is ignored)
/// - A: pause / unpause, and retry on game-over
/// - Start: returns to the cartridge shelf (handled by `CartridgeShelf`)
public struct SnakeGame: View {

    public let input: GameBoyInput
    @State private var state: SnakeState
    @State private var resetCounter: Int = 0   // bumps when we want to restart the task
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
            handleDirection(dir)
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard powerOn, pressed else { return }
            handleA()
        }
        // Including powerOn in the id cancels the loop when off and
        // restarts it (with a fresh sleep) when on.
        .task(id: "\(resetCounter)-\(powerOn)") {
            guard powerOn else { return }
            await runTickLoop()
        }
    }

    // MARK: - Input

    private func handleDirection(_ dir: DPadDirection?) {
        guard let dir else { return }
        if dir.isUp        { state.turn(.up) }
        else if dir.isDown  { state.turn(.down) }
        else if dir.isLeft  { state.turn(.left) }
        else if dir.isRight { state.turn(.right) }
    }

    private func handleA() {
        switch state.phase {
        case .playing, .paused:
            state.togglePause()
        case .dead:
            state.reset()
            resetCounter &+= 1     // re-launches the tick loop
        }
    }

    // MARK: - Tick loop

    private func runTickLoop() async {
        // Sleep first so the player has a beat to orient after load/reset.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(state.stepInterval))
            if Task.isCancelled { return }
            if state.phase == .playing { state.tick() }
            if state.phase == .dead { return }
        }
    }

    // MARK: - Rendering

    private func render(into ctx: inout GraphicsContext, scale: CGSize) {
        // Background
        ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                      color: palette.lcdShade0, scale: scale)

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

        // BEST (right side of HUD) — all-time high for the player.
        let best = state.bestScore
        if best > 0 {
            ctx.draw(
                Text(String(format: "BEST %03d", best))
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 156 * scale.width, y: 12 * scale.height),
                anchor: .leading
            )
        }

        // Mini "alive/dead" indicator on the right of HUD
        let indicatorColor: Color = {
            switch state.phase {
            case .playing: return palette.lcdShade3
            case .paused:  return palette.lcdShade2
            case .dead:    return palette.lcdShade0
            }
        }()
        for dx in [0, 4, 8] {
            ctx.fillPixel(x: 234 + dx, y: 9, width: 3, height: 3,
                          color: indicatorColor, scale: scale)
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

        // Pause / death overlay
        switch state.phase {
        case .paused:
            renderCenteredBanner(into: &ctx, scale: scale, title: "PAUSED", subtitle: "A TO RESUME")
        case .dead:
            let subtitle = state.isNewBest
                ? "NEW BEST!  A: RETRY"
                : "A: RETRY  START: MENU"
            renderCenteredBanner(into: &ctx, scale: scale, title: "GAME OVER", subtitle: subtitle)
        case .playing:
            break
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
    /// Built-in classic Snake.
    static let snake = GameBoyCartridge(
        id: "snake",
        title: "SNAKE",
        blurb: "EAT. GROW. AVOID YOURSELF.",
        make: { input in SnakeGame(input: input) }
    )
}
