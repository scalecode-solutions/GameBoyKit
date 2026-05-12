import Foundation
import Observation
import ConsoleKit

/// Game state for the Snake cartridge. Pure model — no SwiftUI types —
/// so it's straightforward to unit-test. Coordinates are in cell units
/// on a 32×18 grid (the top 3 rows are reserved for the HUD; the play
/// area is rows 3…17).
///
/// Like the Lander + Hopper cartridges, Snake now hosts multiple modes
/// (Classic, Portals, Crusher, Gauntlet) — Classic is the only one
/// wired up in this commit. The `Mode` enum + mode-select phase
/// machinery is in place so future modes plug in as new cases + per-
/// mode tick variants without reshuffling the architecture.
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

    /// Which mode the player is currently inside. v1 ships only
    /// `.classic`; add cases here as new modes land.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        // case portals, crusher, gauntlet — coming in later iterations.

        public var displayName: String {
            switch self {
            case .classic: return "CLASSIC"
            }
        }

        public var briefing: String {
            switch self {
            case .classic: return "EAT. GROW. AVOID YOURSELF."
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case title
        case modeSelect
        case playing
        case paused
        case dead
    }

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

    public private(set) var phase: Phase = .title
    public private(set) var mode: Mode = .classic
    public private(set) var modeSelectCursor: Int = 0

    public private(set) var snake: [GridPoint] = []
    public private(set) var food: GridPoint = .init(x: 0, y: 0)
    public private(set) var direction: Direction = .right
    public private(set) var pendingDirection: Direction? = nil
    public private(set) var score: Int = 0
    public private(set) var stepInterval: Double = 0.16

    /// Tracks whether the just-ended run set a new per-mode best —
    /// view uses this to flash "NEW BEST!" on the game-over banner.
    public private(set) var isNewBest: Bool = false

    // RNG seam — lets tests inject deterministic food placement.
    @ObservationIgnored
    private var rng: any RandomNumberGenerator

    // MARK: - Init

    public init() {
        self.rng = SystemRandomNumberGenerator()
    }

    /// Test-only init that accepts a deterministic RNG.
    public init<R: RandomNumberGenerator>(rng: R) {
        self.rng = rng
    }

    // MARK: - High score (persisted)

    public static let cartridgeId = "snake"

    /// All-time best score for `mode`, read from `UserDefaults` via the
    /// shared `CartridgeScores` service. Zero on a fresh install.
    public func bestScore(for mode: Mode) -> Int {
        CartridgeScores.best(cartridge: Self.cartridgeId, mode: mode.rawValue)
    }

    // MARK: - Phase transitions

    public func openModeSelect() {
        guard phase == .title else { return }
        phase = .modeSelect
        modeSelectCursor = 0
    }

    public func returnToTitle() {
        phase = .title
    }

    public func moveModeSelectCursor(_ delta: Int) {
        guard phase == .modeSelect else { return }
        let n = Mode.allCases.count
        modeSelectCursor = ((modeSelectCursor + delta) % n + n) % n
    }

    public func confirmModeSelection() {
        guard phase == .modeSelect else { return }
        let modes = Mode.allCases
        guard modes.indices.contains(modeSelectCursor) else { return }
        startRun(modes[modeSelectCursor])
    }

    /// Begin a fresh run of the given mode. Resets snake position,
    /// score, speed, food.
    public func startRun(_ mode: Mode) {
        self.mode = mode
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
        stepInterval = 0.16
        isNewBest = false
        phase = .playing
        spawnFood()
    }

    /// After a game-over, restart the same mode.
    public func retryRun() {
        guard phase == .dead else { return }
        startRun(mode)
    }

    /// Back out to the mode-select grid from a dead-screen or paused run.
    public func exitToModeSelect() {
        guard phase == .dead || phase == .paused else { return }
        phase = .modeSelect
    }

    /// Toggle pause/play. No-op when not currently playing or paused.
    public func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default:       break
        }
    }

    // MARK: - Gameplay

    /// Queue a turn. Reversing onto yourself is silently ignored.
    /// Multiple turns within one tick collapse to the last one.
    public func turn(_ dir: Direction) {
        guard phase == .playing else { return }
        if dir == direction.opposite { return }
        pendingDirection = dir
    }

    /// Advance one game tick. Idempotent in any non-playing phase.
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

    // MARK: - Internals

    /// Centralized death path — flips phase and records the final
    /// score to the per-cartridge best-score store if it beats the
    /// existing record for this mode.
    private func die() {
        phase = .dead
        isNewBest = CartridgeScores.recordIfBetter(
            score, cartridge: Self.cartridgeId, mode: mode.rawValue
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
