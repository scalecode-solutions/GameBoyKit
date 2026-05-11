import SwiftUI
import GameBoyKit

/// A toy "game" that proves input wiring works. A green blob walks
/// around the LCD with the D-pad, leaves a trail while A is held, and
/// resets to center when Start is pressed. B shrinks the blob, Select
/// cycles its color.
struct BlobGameView: View {
    let input: GameBoyInput

    @State private var position: CGPoint = .init(x: 0.5, y: 0.5)   // 0...1 normalized
    @State private var trail: [CGPoint] = []
    @State private var size: CGFloat = 1.0
    @State private var hue: Double = 0.32                          // green-ish

    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            ZStack {
                // Trail dots
                ForEach(Array(trail.enumerated()), id: \.offset) { idx, pt in
                    let opacity = Double(idx) / Double(max(trail.count - 1, 1)) * 0.6
                    Circle()
                        .fill(Color(hue: hue, saturation: 0.8, brightness: 0.25).opacity(opacity))
                        .frame(width: 4, height: 4)
                        .position(x: rect.width * pt.x, y: rect.height * pt.y)
                }

                // Blob
                Circle()
                    .fill(Color(hue: hue, saturation: 0.9, brightness: 0.18))
                    .frame(width: 14 * size, height: 14 * size)
                    .position(x: rect.width * position.x, y: rect.height * position.y)

                // Status line at top
                VStack {
                    HStack {
                        Text(statusLine).font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.10))
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    Spacer()
                }
            }
        }
        .onReceive(tick) { _ in step() }
        .onChange(of: input.startPressed) { _, pressed in
            if pressed { reset() }
        }
        .onChange(of: input.selectPressed) { _, pressed in
            if pressed { hue = (hue + 0.18).truncatingRemainder(dividingBy: 1.0) }
        }
        .onChange(of: input.bPressed) { _, pressed in
            size = pressed ? 0.6 : 1.0
        }
    }

    private var statusLine: String {
        let dir = input.dpad.map { $0.rawValue.uppercased() } ?? "---"
        let a = input.aPressed ? "A" : "·"
        let b = input.bPressed ? "B" : "·"
        return "DIR:\(dir) \(a)\(b)"
    }

    private func step() {
        // Move with D-pad
        if let v = input.dpad?.vector {
            let speed: CGFloat = 0.008
            var newPos = position
            newPos.x += CGFloat(v.dx) * speed
            newPos.y += CGFloat(v.dy) * speed
            newPos.x = min(max(newPos.x, 0.04), 0.96)
            newPos.y = min(max(newPos.y, 0.10), 0.96)
            position = newPos
        }

        // Drop a trail point while A is held
        if input.aPressed {
            trail.append(position)
            if trail.count > 80 { trail.removeFirst(trail.count - 80) }
        } else {
            // Fade out by dropping every few frames
            if !trail.isEmpty && Int.random(in: 0..<3) == 0 {
                trail.removeFirst()
            }
        }
    }

    private func reset() {
        position = .init(x: 0.5, y: 0.5)
        trail.removeAll()
    }
}
