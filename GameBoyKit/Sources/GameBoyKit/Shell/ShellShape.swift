import SwiftUI

/// The DMG silhouette: a rounded rectangle with a *much* larger curve on
/// the bottom-right corner than the other three. That asymmetric curve
/// is the single most recognizable cue for "this is a Game Boy."
internal struct ShellShape: InsettableShape {
    /// Corner radius for the three normal corners.
    var standardCorner: CGFloat = 28
    /// Radius for the signature bottom-right curve. Roughly 4x the
    /// standard corner on the real DMG — the most recognizable cue
    /// of the silhouette, so we lean into it.
    var bottomRightCorner: CGFloat = 112
    /// Inset applied by `inset(by:)`. Drawn as a uniform shrink toward the center.
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> ShellShape {
        var copy = self
        copy.inset += amount
        copy.standardCorner = max(0, copy.standardCorner - amount)
        copy.bottomRightCorner = max(0, copy.bottomRightCorner - amount)
        return copy
    }

    func path(in originalRect: CGRect) -> Path {
        let rect = originalRect.insetBy(dx: inset, dy: inset)
        var p = Path()
        let r = standardCorner
        let R = min(bottomRightCorner, min(rect.width, rect.height) * 0.45)

        // top-left → top-right
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )

        // top-right → start of bottom-right curve
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - R))
        p.addArc(
            center: CGPoint(x: rect.maxX - R, y: rect.maxY - R),
            radius: R, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )

        // bottom edge → bottom-left
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )

        // left edge → top-left
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )

        p.closeSubpath()
        return p
    }
}

/// The shell view — base color, subtle vertical gradient, and the
/// inset highlight/shadow that gives it a molded plastic feel.
internal struct ShellBackground: View {
    let palette: GameBoyPalette

    var body: some View {
        ShellShape()
            .fill(
                LinearGradient(
                    colors: [palette.shellTop, palette.shellBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                ShellShape()
                    .strokeBorder(palette.shellEdgeHighlight, lineWidth: 1)
                    .blendMode(.plusLighter)
                    .padding(0.5)
            )
            .overlay(
                ShellShape()
                    .stroke(palette.shellEdgeShadow, lineWidth: 1)
                    .blur(radius: 0.5)
            )
            .shadow(color: .black.opacity(0.30), radius: 24, x: 0, y: 16)
            .shadow(color: .black.opacity(0.10), radius: 4,  x: 0, y: 2)
    }
}
