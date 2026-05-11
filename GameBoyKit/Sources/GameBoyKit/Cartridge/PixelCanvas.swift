import SwiftUI

/// The logical resolution of the in-LCD pixel grid. 160×120 keeps the
/// horizontal density of the original Game Boy (160) while fitting our
/// wider 4:3 bezel.
public enum PixelGrid {
    public static let width:  Int = 160
    public static let height: Int = 120
    public static let size = CGSize(width: width, height: height)
}

/// A pair of logical-pixel coordinates within the 160×120 grid.
/// `(0, 0)` is the top-left. Values are clamped to the grid by helpers
/// that draw with them.
public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// Helpers attached to `GraphicsContext` for drawing pixel-snapped
/// rectangles, lines of pixels, and tiles inside a `PixelCanvas`.
public extension GraphicsContext {

    /// Fill a logical rectangle in the 160×120 grid.
    /// The `scale` is the actual-pixels-per-logical-pixel transform.
    mutating func fillPixel(
        x: Int, y: Int, width: Int = 1, height: Int = 1,
        color: Color,
        scale: CGSize
    ) {
        let rect = CGRect(
            x: CGFloat(x) * scale.width,
            y: CGFloat(y) * scale.height,
            width:  CGFloat(width)  * scale.width,
            height: CGFloat(height) * scale.height
        )
        fill(Path(rect), with: .color(color))
    }

    /// Convenience overload taking a `PixelPoint`.
    mutating func fillPixel(
        _ point: PixelPoint, width: Int = 1, height: Int = 1,
        color: Color,
        scale: CGSize
    ) {
        fillPixel(x: point.x, y: point.y, width: width, height: height, color: color, scale: scale)
    }
}

/// A `Canvas` that exposes a `(GraphicsContext, CGSize) -> Void` draw
/// closure operating in logical 160×120 coordinates, with the scale
/// factor pre-computed for you. Hosts of `PixelCanvas` (typically game
/// cartridges) hand off a `draw` function and never have to think
/// about the actual pixel size of the LCD on screen.
public struct PixelCanvas: View {
    /// The draw closure runs on the main actor (Canvas's renderer is
    /// invoked during view rendering), so it's free to capture
    /// `@Environment` values and other main-isolated state.
    public typealias Draw = @MainActor (inout GraphicsContext, CGSize) -> Void

    private let draw: Draw

    public init(draw: @escaping Draw) {
        self.draw = draw
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let scale = CGSize(
                width:  size.width  / CGFloat(PixelGrid.width),
                height: size.height / CGFloat(PixelGrid.height)
            )
            var ctx = context
            MainActor.assumeIsolated {
                draw(&ctx, scale)
            }
        }
        .aspectRatio(
            CGFloat(PixelGrid.width) / CGFloat(PixelGrid.height),
            contentMode: .fit
        )
        .drawingGroup()   // rasterize once per frame; helps with chunky fills
    }
}
