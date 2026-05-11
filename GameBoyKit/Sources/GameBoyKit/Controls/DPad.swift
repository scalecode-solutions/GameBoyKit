import SwiftUI

/// The plus-shaped directional pad. A single drag gesture covers the
/// whole cross plus its diagonal hit-zones, so a finger sliding around
/// the pad generates a smooth stream of 8-way directions just like a
/// real D-pad. Updates `GameBoyInput.dpad`.
internal struct DPad: View {
    let palette: GameBoyPalette
    let input: GameBoyInput

    @State private var current: DPadDirection? = nil
    @State private var hapticTrigger: Int = 0
    @Environment(\.deviceSettings) private var settings

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let armWidth = size / 3.0

            ZStack {
                // Cross shape — two rounded rectangles overlapping at center
                Group {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .frame(width: armWidth, height: size)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .frame(width: size, height: armWidth)
                }
                .compositingGroup()
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.dpadHighlight, palette.dpad],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: palette.dpadShadow, radius: 2, x: 0, y: 2)

                // Center disc with subtle highlight
                Circle()
                    .fill(palette.dpad)
                    .frame(width: armWidth * 0.6, height: armWidth * 0.6)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                // Direction indicators (tiny embossed arrows)
                arrows(size: size, armWidth: armWidth)
            }
            .frame(width: size, height: size)
            .scaleEffect(current == nil ? 1.0 : 0.98)
            .animation(.easeOut(duration: 0.08), value: current)
            .contentShape(Rectangle())                       // full square is touchable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let offset = CGPoint(
                            x: (value.location.x - center.x) / (size / 2),
                            y: (value.location.y - center.y) / (size / 2)
                        )
                        let direction = DPadDirection.from(offset: offset)
                        if direction != current {
                            current = direction
                            input.setDPad(direction)
                            if direction != nil && settings.hapticsEnabled {
                                hapticTrigger &+= 1
                            }
                        }
                    }
                    .onEnded { _ in
                        current = nil
                        input.setDPad(nil)
                    }
            )
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: hapticTrigger)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func arrows(size: CGFloat, armWidth: CGFloat) -> some View {
        let inset = armWidth * 0.35
        let arrowColor = Color.black.opacity(0.35)
        // Up
        Triangle().fill(arrowColor)
            .frame(width: armWidth * 0.30, height: armWidth * 0.20)
            .offset(y: -(size / 2 - inset))
        // Down
        Triangle().fill(arrowColor)
            .frame(width: armWidth * 0.30, height: armWidth * 0.20)
            .rotationEffect(.degrees(180))
            .offset(y:  (size / 2 - inset))
        // Left
        Triangle().fill(arrowColor)
            .frame(width: armWidth * 0.30, height: armWidth * 0.20)
            .rotationEffect(.degrees(-90))
            .offset(x: -(size / 2 - inset))
        // Right
        Triangle().fill(arrowColor)
            .frame(width: armWidth * 0.30, height: armWidth * 0.20)
            .rotationEffect(.degrees(90))
            .offset(x:  (size / 2 - inset))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
