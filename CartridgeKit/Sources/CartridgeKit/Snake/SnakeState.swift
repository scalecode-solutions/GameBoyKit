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

    /// Which mode the player is currently inside.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        case portals
        // case crusher, gauntlet — coming in later iterations.

        public var displayName: String {
            switch self {
            case .classic: return "CLASSIC"
            case .portals: return "PORTALS"
            }
        }

        public var briefing: String {
            switch self {
            case .classic: return "EAT. GROW. AVOID YOURSELF."
            case .portals: return "WARP. HEIST THE VAULT. ESCAPE."
            }
        }
    }

    /// Treasure rarity tiers for the Portals mode side-map heist.
    /// Each tier carries a score multiplier and a spawn weight; the
    /// weights are normalized at roll time so the rarity ratios stay
    /// stable even if values shift.
    public enum TreasureKind: Int, CaseIterable, Sendable, Codable {
        case x2  = 2
        case x5  = 5
        case x10 = 10
        case x20 = 20
        case x50 = 50

        public var multiplier: Int { rawValue }

        /// Spawn weight (sums to 100 across all cases).
        public var weight: Int {
            switch self {
            case .x2:  return 45
            case .x5:  return 25
            case .x10: return 15
            case .x20: return 10
            case .x50: return  5
            }
        }

        /// Short display label drawn next to the treasure sprite.
        public var label: String { "x\(rawValue)" }
    }

    /// A teleport pair endpoint. Width 1 = pair-linked teleport (snake
    /// head crossing into endpoint A appears at endpoint B). Width 2 =
    /// gateway to/from the side map.
    public struct Portal: Hashable, Sendable {
        public var x: Int      // leftmost cell
        public var y: Int      // top cell
        public var width: Int  // 1 or 2 (currently)
        public init(x: Int, y: Int, width: Int) {
            self.x = x; self.y = y; self.width = width
        }
        /// All cells this portal occupies.
        public var cells: [GridPoint] {
            (0..<width).map { GridPoint(x: x + $0, y: y) }
        }
    }

    /// Side-map persistence state.
    public enum SideMapState: Sendable, Equatable {
        case uninitialized   // never visited
        case fresh           // generated, treasure present, hasn't been picked up
        case resolved        // treasure picked up + delivered/lost; re-roll on next entry
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

    // MARK: - Portals-mode state

    /// 1-wide pair-linked teleport endpoints on the main map. Snake
    /// head crossing into pair.0 appears at pair.1 (and vice versa).
    public private(set) var portalPairs: [(Portal, Portal)] = []

    /// 2-wide gateway anchor cells on the main and side maps. Crossing
    /// into one warps the snake to the other; entering the side
    /// gateway while `isCarryingTreasure` triggers the bonus payout.
    public private(set) var mainGateway: Portal? = nil
    public private(set) var sideGateway: Portal? = nil

    /// Whether the snake is currently on the side map (true) or the
    /// main map (false). Drives which obstacles + portals are active
    /// each tick and which terrain the view paints.
    public private(set) var inSideMap: Bool = false

    /// Side-map obstacles (random count + positions per fresh cycle).
    public private(set) var sideMapObstacles: [GridPoint] = []

    /// Treasure position on the side map. Nil while the treasure
    /// hasn't spawned (uninitialized) or has been picked up.
    public private(set) var sideMapTreasure: GridPoint? = nil

    /// Multiplier tier of the currently-staged side-map treasure.
    public private(set) var sideMapTreasureKind: TreasureKind = .x2

    /// Current persistence state of the side map. `fresh` means the
    /// snake can scout the room repeatedly without re-rolling the
    /// treasure or the obstacle layout.
    public private(set) var sideMapState: SideMapState = .uninitialized

    /// True between the snake's head touching the side-map treasure
    /// and either delivering it (exit gateway → bonus) or losing it
    /// (death → forfeit).
    public private(set) var isCarryingTreasure: Bool = false
    public private(set) var carriedTreasureKind: TreasureKind = .x2

    /// Counter that drives the head's carry-indicator pulse + the
    /// treasure sprite's twinkle animation. Advanced by the view.
    public private(set) var animationTick: Int = 0

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
    /// score, speed, food, and any mode-specific state.
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
        // Reset Portals state.
        portalPairs = []
        mainGateway = nil
        sideGateway = nil
        inSideMap = false
        sideMapObstacles = []
        sideMapTreasure = nil
        sideMapState = .uninitialized
        isCarryingTreasure = false
        // Mode-specific setup.
        if mode == .portals {
            setupPortalsMode()
        }
        phase = .playing
        spawnFood()
    }

    /// Called by the view each animation frame (60Hz) to drive
    /// per-frame visual effects (treasure twinkle, carry-indicator
    /// pulse). Independent of the game tick.
    public func bumpAnimationTick() {
        animationTick &+= 1
    }

    // MARK: - Portals mode setup

    /// Configures the main-map portal layout: two 1-wide pair-linked
    /// teleports + one 2-wide gateway. Layout is fixed (not procgen)
    /// so players can build muscle memory of the warp geometry.
    private func setupPortalsMode() {
        // Pair 1: horizontal warp on the middle row.
        let pair1 = (
            Portal(x: 0,            y: 10, width: 1),
            Portal(x: Self.cols - 1, y: 10, width: 1)
        )
        // Pair 2: vertical warp on column 8.
        let pair2 = (
            Portal(x: 8,  y: Self.playRowStart,   width: 1),
            Portal(x: 8,  y: Self.playRowEnd - 1, width: 1)
        )
        portalPairs = [pair1, pair2]
        // 2-wide gateway on the right side of the main map.
        mainGateway = Portal(x: Self.cols - 2, y: 5, width: 2)
        // Side-map's matching gateway sits at the LEFT side so the
        // snake emerges "into" the side map's space.
        sideGateway = Portal(x: 0, y: 5, width: 2)
    }

    /// Generate (or re-generate) the side-map's obstacle layout +
    /// treasure. Called the first time the snake enters the gateway,
    /// and again after any treasure resolution (delivered or lost).
    private func generateSideMap() {
        // Random obstacle count in [3, 12].
        let obstacleCount = Int.random(in: 3...12, using: &rng)
        var occupied = Set<GridPoint>()
        // Sample the side-map entry cells (snake will appear here on
        // transition) so we don't place an obstacle ON the entry.
        if let g = sideGateway {
            for c in g.cells { occupied.insert(c) }
            // Also reserve a 3-cell corridor in front of the gateway
            // so the snake has somewhere to go.
            for dx in 1...3 {
                occupied.insert(GridPoint(x: g.x + dx, y: g.y))
                occupied.insert(GridPoint(x: g.x + dx, y: g.y + 1))
            }
        }
        var obstacles: [GridPoint] = []
        var attempts = 0
        while obstacles.count < obstacleCount && attempts < 200 {
            attempts += 1
            let cand = GridPoint(
                x: Int.random(in: 0..<Self.cols, using: &rng),
                y: Int.random(in: Self.playRowStart..<Self.playRowEnd, using: &rng)
            )
            if !occupied.contains(cand) {
                occupied.insert(cand)
                obstacles.append(cand)
            }
        }
        sideMapObstacles = obstacles
        // Roll a treasure kind weighted by rarity.
        sideMapTreasureKind = rollTreasureKind()
        // Place treasure at a random open cell ≥ 5 cells from the
        // entry gateway so it's never a "grab on the way in".
        var treasure: GridPoint? = nil
        attempts = 0
        let entryX = sideGateway?.x ?? 0
        let entryY = sideGateway?.y ?? 8
        while treasure == nil && attempts < 200 {
            attempts += 1
            let cand = GridPoint(
                x: Int.random(in: 0..<Self.cols, using: &rng),
                y: Int.random(in: Self.playRowStart..<Self.playRowEnd, using: &rng)
            )
            let dx = cand.x - entryX, dy = cand.y - entryY
            if dx * dx + dy * dy < 25 { continue }       // < 5 cell radius
            if occupied.contains(cand) { continue }
            treasure = cand
        }
        sideMapTreasure = treasure
        sideMapState = .fresh
    }

    private func rollTreasureKind() -> TreasureKind {
        let total = TreasureKind.allCases.map(\.weight).reduce(0, +)
        let pick = Int.random(in: 0..<total, using: &rng)
        var running = 0
        for kind in TreasureKind.allCases {
            running += kind.weight
            if pick < running { return kind }
        }
        return .x2
    }

    // MARK: - Portals teleport + gateway helpers

    /// If `cell` matches one endpoint of a 1-wide portal pair, returns
    /// the paired endpoint's cell (so the snake head warps to it).
    /// Returns nil if no pair is touched.
    private func portalTeleport(for cell: GridPoint) -> GridPoint? {
        for (a, b) in portalPairs {
            if a.cells.contains(cell) { return b.cells[0] }
            if b.cells.contains(cell) { return a.cells[0] }
        }
        return nil
    }

    /// True if `cell` is part of the currently-active 2-wide gateway
    /// (main when on main map, side when in side map).
    private func isGatewayCell(_ cell: GridPoint) -> Bool {
        let g = inSideMap ? sideGateway : mainGateway
        return g?.cells.contains(cell) == true
    }

    /// Snap the snake to a collapsed point at `head`, length preserved.
    /// Each segment occupies `head` so subsequent ticks "unfurl" the
    /// snake naturally as it moves forward — a clean wormhole visual
    /// without needing to lay body cells off-screen.
    private func collapseSnake(at head: GridPoint) {
        snake = Array(repeating: head, count: snake.count)
    }

    /// Triggered when the snake head crosses the active 2-wide gateway.
    /// Flips `inSideMap`, generates the side map on first entry, and
    /// resolves any in-flight treasure delivery on exit.
    private func crossGateway() {
        if inSideMap {
            // Leaving side → main. If carrying, the heist resolves.
            if isCarryingTreasure {
                let bonus = snake.count * sideMapObstacles.count * carriedTreasureKind.multiplier
                score += bonus
                isCarryingTreasure = false
                sideMapState = .resolved        // re-roll on next entry
            }
            inSideMap = false
            if let g = mainGateway {
                collapseSnake(at: g.cells[0])
            }
        } else {
            // Entering side. Generate room if needed.
            if sideMapState != .fresh {
                generateSideMap()
            }
            inSideMap = true
            if let g = sideGateway {
                collapseSnake(at: g.cells[0])
            }
        }
        // After a transition we need a fresh food spawn on the new map.
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
        var newHead = GridPoint(x: head.x + direction.dx, y: head.y + direction.dy)

        // 1-wide portal teleport (Portals mode only). Applied to the
        // raw newHead BEFORE wall checks so a head moving "off" the
        // map at a portal cell teleports instead of dying.
        if mode == .portals, let warped = portalTeleport(for: newHead) {
            newHead = warped
        }

        // Wall collision
        if newHead.x < 0 || newHead.x >= Self.cols
            || newHead.y < Self.playRowStart || newHead.y >= Self.playRowEnd {
            die()
            return
        }

        // 2-wide gateway crossing (Portals mode). Cross when the head
        // moves onto a gateway cell — flips maps + handles treasure
        // delivery on exit. Body collapses to the new gateway anchor
        // so the snake unfurls onto the new map.
        if mode == .portals && isGatewayCell(newHead) {
            crossGateway()
            return
        }

        // Side-map obstacle collision = death.
        if mode == .portals && inSideMap && sideMapObstacles.contains(newHead) {
            die()
            return
        }

        // Self collision — exclude the tail because it moves out this step
        if snake.dropLast().contains(newHead) {
            die()
            return
        }

        snake.insert(newHead, at: 0)

        // Treasure pickup (Portals side map only). The treasure
        // vanishes; carry state activates; bonus is realized only when
        // the snake exits back through the side gateway.
        if mode == .portals && inSideMap,
           let t = sideMapTreasure, newHead == t {
            sideMapTreasure = nil
            isCarryingTreasure = true
            carriedTreasureKind = sideMapTreasureKind
        }

        if newHead == food {
            score += 10
            stepInterval = max(0.06, stepInterval * 0.94)   // speed up
            spawnFood()
        } else {
            snake.removeLast()
        }
    }

    // MARK: - Internals

    /// Centralized death path — flips phase, forfeits any in-flight
    /// treasure (heist lost), and records the final score to the
    /// per-cartridge best-score store if it beats the existing record
    /// for this mode.
    private func die() {
        phase = .dead
        if isCarryingTreasure {
            // Heist failed — bonus forfeited. Side map will re-roll
            // its layout the next time the player enters.
            isCarryingTreasure = false
            sideMapState = .resolved
        }
        isNewBest = CartridgeScores.recordIfBetter(
            score, cartridge: Self.cartridgeId, mode: mode.rawValue
        )
    }

    private func spawnFood() {
        // Avoid an infinite loop if the player ever fills the board.
        let totalCells = Self.cols * (Self.playRowEnd - Self.playRowStart)
        if snake.count >= totalCells { return }

        // Build the set of cells the food can't occupy.
        var blocked = Set(snake)
        if mode == .portals && inSideMap {
            for o in sideMapObstacles { blocked.insert(o) }
            if let t = sideMapTreasure { blocked.insert(t) }
        }

        var attempts = 0
        var candidate: GridPoint
        repeat {
            candidate = GridPoint(
                x: Int.random(in: 0..<Self.cols, using: &rng),
                y: Int.random(in: Self.playRowStart..<Self.playRowEnd, using: &rng)
            )
            attempts += 1
            if attempts > 500 { break }     // give up rather than spin forever
        } while blocked.contains(candidate)
        food = candidate
    }
}
