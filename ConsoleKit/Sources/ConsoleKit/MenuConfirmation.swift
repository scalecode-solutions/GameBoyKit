import SwiftUI
import GameBoyKit

/// Modal "Return to library?" dialog rendered over a running game.
/// Driven by `CartridgeShelf` — when the MENU button is pressed
/// mid-game, this overlays the LCD, dims the playfield behind it,
/// and waits for YES (A on yes) or NO (A on no, B, or MENU again).
internal struct MenuConfirmation: View {

    enum Selection { case yes, no }

    let input: GameBoyInput
    let palette: GameBoyPalette
    let onConfirm: () -> Void
    let onCancel:  () -> Void

    // Default to NO so a fat-finger MENU + A doesn't nuke a run.
    @State private var selection: Selection = .no

    var body: some View {
        PixelCanvas { ctx, scale in
            // Dim the game behind by painting a translucent shade3.
            ctx.fillPixel(x: 0, y: 0, width: 256, height: 144,
                          color: palette.lcdShade3.opacity(0.65), scale: scale)

            // Dialog box
            let boxX = 32, boxY = 36, boxW = 192, boxH = 72
            ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: boxH,
                          color: palette.lcdShade0, scale: scale)
            // Border (1-pixel frame)
            ctx.fillPixel(x: boxX, y: boxY, width: boxW, height: 1,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: boxX, y: boxY + boxH - 1, width: boxW, height: 1,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: boxX, y: boxY, width: 1, height: boxH,
                          color: palette.lcdShade3, scale: scale)
            ctx.fillPixel(x: boxX + boxW - 1, y: boxY, width: 1, height: boxH,
                          color: palette.lcdShade3, scale: scale)

            // Title
            ctx.draw(
                Text("RETURN TO LIBRARY?")
                    .font(.system(size: 12 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 128 * scale.width, y: 54 * scale.height),
                anchor: .center
            )

            // YES / NO row
            let row = 80
            drawOption(into: &ctx, scale: scale,
                       label: "YES", centerX: 96,  y: row, isSelected: selection == .yes)
            drawOption(into: &ctx, scale: scale,
                       label: "NO",  centerX: 160, y: row, isSelected: selection == .no)

            // Controls hint
            ctx.draw(
                Text("◁▷ PICK   A: OK   B: CANCEL")
                    .font(.system(size: 8 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 128 * scale.width, y: 100 * scale.height),
                anchor: .center
            )
        }
        .onChange(of: input.dpad) { _, dir in
            guard let dir else { return }
            if dir.isLeft  { selection = .yes }
            if dir.isRight { selection = .no  }
        }
        .onChange(of: input.aPressed) { _, pressed in
            guard pressed else { return }
            switch selection {
            case .yes: onConfirm()
            case .no:  onCancel()
            }
        }
        .onChange(of: input.bPressed) { _, pressed in
            if pressed { onCancel() }
        }
        .onChange(of: input.menuPressed) { _, pressed in
            // Pressing MENU again while the dialog is open dismisses it.
            if pressed { onCancel() }
        }
    }

    private func drawOption(
        into ctx: inout GraphicsContext,
        scale: CGSize,
        label: String,
        centerX: Int,
        y: Int,
        isSelected: Bool
    ) {
        if isSelected {
            // Highlight pill behind the label
            ctx.fillPixel(x: centerX - 17, y: y - 5, width: 34, height: 11,
                          color: palette.lcdShade3, scale: scale)
        }
        ctx.draw(
            Text(label)
                .font(.system(size: 10 * scale.height,
                              weight: .heavy,
                              design: .monospaced))
                .foregroundColor(isSelected ? palette.lcdShade0 : palette.lcdShade3),
            at: CGPoint(x: CGFloat(centerX) * scale.width,
                        y: CGFloat(y) * scale.height),
            anchor: .center
        )
    }
}
