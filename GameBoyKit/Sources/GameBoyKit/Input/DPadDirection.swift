import Foundation
import CoreGraphics

/// Eight-way direction emitted by the D-pad. `nil` on `GameBoyInput.dpad`
/// represents "not pressed". Diagonals are emitted when the touch lands in
/// the diagonal hit-zone of the D-pad cross.
public enum DPadDirection: String, CaseIterable, Sendable, Hashable {
    case up, upRight, right, downRight, down, downLeft, left, upLeft

    /// Unit vector pointing in this direction. `+y` is down (screen coordinates).
    public var vector: CGVector {
        switch self {
        case .up:        return .init(dx:  0, dy: -1)
        case .upRight:   return .init(dx:  0.7071, dy: -0.7071)
        case .right:     return .init(dx:  1, dy:  0)
        case .downRight: return .init(dx:  0.7071, dy:  0.7071)
        case .down:      return .init(dx:  0, dy:  1)
        case .downLeft:  return .init(dx: -0.7071, dy:  0.7071)
        case .left:      return .init(dx: -1, dy:  0)
        case .upLeft:    return .init(dx: -0.7071, dy: -0.7071)
        }
    }

    /// True if this direction has an upward component.
    public var isUp: Bool { self == .up || self == .upLeft || self == .upRight }
    /// True if this direction has a downward component.
    public var isDown: Bool { self == .down || self == .downLeft || self == .downRight }
    /// True if this direction has a leftward component.
    public var isLeft: Bool { self == .left || self == .upLeft || self == .downLeft }
    /// True if this direction has a rightward component.
    public var isRight: Bool { self == .right || self == .upRight || self == .downRight }

    /// Build a direction from a normalized offset within the D-pad bounds
    /// (origin at center, range roughly -1...1). Returns `nil` for tiny
    /// offsets in the dead zone.
    public static func from(offset: CGPoint, deadZone: CGFloat = 0.15) -> DPadDirection? {
        let magnitude = (offset.x * offset.x + offset.y * offset.y).squareRoot()
        guard magnitude > deadZone else { return nil }
        // Angle measured clockwise from "up" so we can bucket into 8 slices.
        let angle = atan2(offset.x, -offset.y)               // -π ... π, 0 = up
        let normalized = (angle + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        let slice = Int((normalized / (.pi / 4)).rounded()) % 8
        return [DPadDirection.up, .upRight, .right, .downRight,
                .down, .downLeft, .left, .upLeft][slice]
    }
}
