import SwiftUI
import GameBoyKit

/// Placeholder cartridge factory so we can show the menu has multiple
/// rows even before more games exist. Renders a "COMING SOON" stub
/// when loaded.
extension GameBoyCartridge {
    static func comingSoon(id: String, title: String) -> GameBoyCartridge {
        GameBoyCartridge(
            id: id,
            title: title,
            blurb: "COMING SOON",
            make: { _ in ComingSoonView(title: title) }
        )
    }
}

private struct ComingSoonView: View {
    let title: String
    @Environment(\.gameBoyPalette) private var palette

    var body: some View {
        PixelCanvas { ctx, scale in
            ctx.fillPixel(x: 0, y: 0, width: 160, height: 120,
                          color: palette.lcdShade0, scale: scale)
            ctx.draw(
                Text(title)
                    .font(.system(size: 16 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade3),
                at: CGPoint(x: 80 * scale.width, y: 50 * scale.height),
                anchor: .center
            )
            ctx.draw(
                Text("COMING SOON")
                    .font(.system(size: 10 * scale.height,
                                  weight: .heavy,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 80 * scale.width, y: 68 * scale.height),
                anchor: .center
            )
            ctx.draw(
                Text("START: MENU")
                    .font(.system(size: 8 * scale.height,
                                  weight: .bold,
                                  design: .monospaced))
                    .foregroundColor(palette.lcdShade2),
                at: CGPoint(x: 80 * scale.width, y: 100 * scale.height),
                anchor: .center
            )
        }
    }
}
