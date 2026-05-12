import Foundation
import Observation
import ConsoleKit

/// Game state for the Snake cartridge. Pure model — no SwiftUI types —
/// so it's straightforward to unit-test. Coordinates are in cell units
/// on a 20×15 grid (the top 3 rows are reserved for the HUD; the
/// 20×12 play area is rows 3…14).
@MainActor
@Observable
public final class SnakeState {

    // MARK: - Geometry

    // 256×144 logical LCD with 8×8 cells → 32 cols × 18 rows.
    public static let cols          = 32
    public static let rows          = 18
    public static let hudRows       = 3            // 0..<3 reserved
    public static var playRowStart: Int { hudRows }
    public static var playRowEnd:   Int { rows }   // exclusive

    // MARK: - Types

    public enum Phase: Equatable, Sendable { case playing, paused, dead }

    public enum Direction: CaseIterable, Sendable {
        case up, down, left, right
        public var dx: Int { switch self { case .left: -1; case .right: 1; default: 0 } }
        public var dy: Int { switch self { case .up:   -1; case .down:  1; default: 0 } }
        public var opposite: Direction {
            switch self {
            case .up:    return .down
            case .down:  return .up
            case .left:  return .right
            case .right: return .left
            }
        }
    }

    public struct GridPoint: Hashable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    // MARK: - State

    public private(set) var snake: [GridPoint] = []
    public private(set) var food: GridPoint = .init(x: 0, y: 0)
    public private(set) var direction: Direction = .right
    public private(set) var pendingDirection: Direction? = nil
    public private(set) var score: Int = 0
    public private(set) var phase: Phase = .playing
    public private(set) var stepInterval: Double = 0.16

    // RNG seam — lets tests inject deterministic food placement.
    @ObservationIgnored
    private var rng: any RandomNumberGenerator

    // MARK: - Init

    public init() {
        self.rng = SystemRandomNumberGenerator()
        reset()
    }

    /// Test-only init that accepts a deterministic RNG.
    public init<R: RandomNumberGenerator>(rng: R) {
        self.rng = rng
        reset()
    }

    // MARK: - Commands

    /// Queue a turn. Reversing onto yourself is silently ignored.
    /// Multiple turns within one tick collapse to the last one.
    public func turn(_ dir: Direction) {
        guard phase == .playing else { return }
        if dir == direction.opposite { return }
        pendingDirection = dir
    }

    /// Toggle pause/play. No-op when dead.
    public func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        case .dead:    break
        }
    }

    /// Advance one game tick. Idempotent when paused or dead.
    public func tick() {
        guard phase == .playing else { return }

        if let next = pendingDirection {
            direction = next
            pendingDirection = nil
        }

        let head = snake[0]
        let newHead = GridPoint(x: head.x + direction.dx, y: head.y + direction.dy)

        // Wall collision
        if newHead.x < 0 || newHead.x >= Self.cols
            || newHead.y < Self.playRowStart || newHead.y >= Self.playRowEnd {
            die()
            return
        }
        // Self collision — exclude the tail because it moves out this step
        if snake.dropLast().contains(newHead) {
            die()
            return
        }

        snake.insert(newHead, at: 0)
        if newHead == food {
            score += 10
            stepInterval = max(0.06, stepInterval * 0.94)   // speed up
            spawnFood()
        } else {
            snake.removeLast()
        }
    }

    /// Reset to a fresh game.
    public func reset() {
        let cx = Self.cols / 2
        let cy = Self.playRowStart + (Self.playRowEnd - Self.playRowStart) / 2
        snake = [
            GridPoint(x: cx,     y: cy),
            GridPoint(x: cx - 1, y: cy),
            GridPoint(x: cx - 2, y: cy)
        ]
        direction = .right
        pendingDirection = nil
        score = 0
        phase = .playing
        stepInterval = 0.16
        isNewBest = false
        spawnFood()
    }

    // MARK: - High score (persisted)

    /// Cartridge + mode identifiers used as the `CartridgeScores` key.
    /// Static so the view can read the best score on game-over without
    /// holding a state reference (e.g., during the result banner).
    public static let cartridgeId = "snake"
    public static let modeId      = "classic"

    /// All-time best score for Snake, read from `UserDefaults` via the
    /// shared `CartridgeScores` service. Zero on a fresh install.
    public var bestScore: Int {
        CartridgeScores.best(cartridge: Self.cartridgeId, mode: Self.modeId)
    }

    /// Tracks whether the just-ended run set a new best — view uses
    /// this to flash "NEW BEST!" on the game-over banner.
    public private(set) var isNewBest: Bool = false

    // MARK: - Internals

    /// Centralized death path — flips phase and records the final
    /// score to the per-cartridge best-score store if it beats the
    /// existing record.
    private func die() {
        phase = .dead
        isNewBest = CartridgeScores.recordIfBetter(
            score, cartridge: Self.cartridgeId, mode: Self.modeId
        )
    }

    private func spawnFood() {
        // Avoid an infinite loop if the player ever fills the board.
        let totalCells = Self.cols * (Self.playRowEnd - Self.playRowStart)
        if snake.count >= totalCells { return }

        var candidate: GridPoint
        repeat {
            candidate = GridPoint(
                x: Int.random(in: 0..<Self.cols, using: &rng),
                y: Int.random(in: Self.playRowStart..<Self.playRowEnd, using: &rng)
            )
        } while snake.contains(candidate)
        food = candidate
    }
}
