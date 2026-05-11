import Foundation
import Observation

/// Game state for the Hopper cartridge — the legally-distinct-but-
/// spiritually-Frogger road & river crossing game. Pure model, no
/// SwiftUI types; straightforward to unit-test.
///
/// Like the Lander cartridge, Hopper hosts multiple modes (Classic /
/// Endless / Night Shift / Heist) — Classic is the only one wired up
/// in v1. The Mode enum + mode-select phase machinery is in place so
/// future modes plug in as new cases + per-mode tick variants without
/// reshuffling the architecture.
@MainActor
@Observable
public final class HopperState {

    // MARK: - Grid (256×144 logical LCD in 8×8 cells)

    public static let cols:     Int = 32
    public static let rows:     Int = 18
    public static let cellSize: Int = 8

    /// Top of the play area in cell rows — the HUD strip occupies
    /// rows 0..<hudRows.
    public static let hudRows: Int = 2

    /// Cell row containing the lily-pad bank (the win goal). Touching
    /// this row at all = victory in v1.
    public static let goalRow: Int = 2

    /// Cell row holding the median strip between river and road.
    public static let medianRow: Int = 8

    /// Cell row where the frog respawns / starts each life.
    public static let startRow: Int = 16

    /// Cell column where the frog starts each life (centered).
    public static let frogStartCol: Int = 16

    /// Initial lives per Classic run. Future modes may differ.
    public static let classicLives: Int = 3

    /// Initial timer per Classic crossing (seconds × 60Hz ticks).
    public static let classicTimeTicks: Int = 30 * 60

    // MARK: - Types

    /// Which mode the player is currently inside. v1 ships only
    /// `.classic`; add cases here as new modes land.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        // case endless, nightShift, heist — coming in later iterations.

        public var displayName: String {
            switch self {
            case .classic: return "CLASSIC"
            }
        }

        public var briefing: String {
            switch self {
            case .classic: return "ROAD. RIVER. REACH THE TOP."
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case title
        case modeSelect
        case playing
        case paused
        case won
        case dead
    }

    /// Cardinal hop direction the view translates D-pad input into.
    /// Diagonals collapse to the dominant axis (vertical wins ties).
    public enum HopDirection: Sendable {
        case up, down, left, right
    }

    public enum LaneKind: Sendable, Equatable {
        case road    // touching an entity = die
        case river   // entity = log (ride it); empty water = drown
    }

    public enum LaneDirection: Sendable { case left, right }

    /// A horizontal hazard lane — road full of cars or a river of logs.
    public struct Lane: Sendable {
        public let row:          Int
        public let kind:         LaneKind
        public let direction:    LaneDirection
        public let speed:        Double      // cells per tick
        public let entityWidth:  Int         // cells (visual)
        public let entityCount:  Int
        /// Visual variant — picks a sprite shape so cars/logs aren't
        /// identical across lanes. 0..<3.
        public let visualVariant: Int
    }

    /// A single car or log in continuous cell-space.
    public struct Entity: Sendable {
        public var x: Double                  // cell x; can be off-screen for wrap
    }

    /// Reason the frog died this life. Surfaced to the result banner.
    public enum DeathCause: Sendable, Equatable {
        case crushed       // hit by a car
        case drowned       // in river, not on a log
        case carriedOff    // log rode the frog off the screen
        case timeUp
    }

    // MARK: - State

    public private(set) var phase: Phase = .title
    public private(set) var mode: Mode = .classic
    public private(set) var modeSelectCursor: Int = 0

    /// Hazard lanes for the current mode.
    public private(set) var lanes: [Lane] = []

    /// Entities per lane (parallel to `lanes`). Outer index = lane idx,
    /// inner = entity idx.
    public private(set) var entities: [[Entity]] = []

    /// Frog position in cell coordinates (cardinal grid).
    public private(set) var frogX: Int = 0
    public private(set) var frogY: Int = 0

    /// Frog's continuous X (logical-pixel-resolution Double measured in
    /// cells). Used while riding a log so the frog smoothly drifts with
    /// the log between hops. Reset to `Double(frogX)` whenever the frog
    /// isn't on a log.
    public private(set) var frogPixelX: Double = 0

    /// When the frog is on a log, the lane + entity it's riding.
    public private(set) var ridingLane: Int? = nil
    public private(set) var ridingEntity: Int? = nil

    public private(set) var lives: Int = 0
    public private(set) var score: Int = 0
    public private(set) var timeRemainingTicks: Int = 0
    public private(set) var lastDeath: DeathCause? = nil

    /// Highest row reached (lowest Y value) during the current life —
    /// used by future endless mode scoring; harmless in Classic.
    public private(set) var bestRow: Int = 0

    // MARK: - Init

    public init() {
        resetToTitle()
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

    public func startRun(_ mode: Mode) {
        self.mode = mode
        setupLanes(for: mode)
        lives = Self.classicLives
        score = 0
        timeRemainingTicks = Self.classicTimeTicks
        lastDeath = nil
        bestRow = Self.startRow
        respawnFrog()
        phase = .playing
    }

    public func retryRun() {
        guard phase == .dead || phase == .won else { return }
        startRun(mode)
    }

    public func exitToModeSelect() {
        guard phase == .dead || phase == .won else { return }
        phase = .modeSelect
    }

    public func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default:       break
        }
    }

    public func resetToTitle() {
        phase = .title
        mode = .classic
        modeSelectCursor = 0
        lanes = []
        entities = []
        frogX = 0
        frogY = 0
        frogPixelX = 0
        ridingLane = nil
        ridingEntity = nil
        lives = 0
        score = 0
        timeRemainingTicks = 0
        lastDeath = nil
        bestRow = 0
    }

    // MARK: - Lane setup

    private func setupLanes(for mode: Mode) {
        switch mode {
        case .classic:
            // Five river lanes (rows 3-7, filling all visible water),
            // median row 8, four road lanes. The topmost river lane
            // sits directly under the goal row so the frog hops from
            // a log onto a lily pad — classic Frogger layout. Speeds
            // and directions alternate so crossing isn't memorized.
            lanes = [
                Lane(row: 3, kind: .river, direction: .left,  speed: 0.05, entityWidth: 4, entityCount: 3, visualVariant: 0),
                Lane(row: 4, kind: .river, direction: .right, speed: 0.04, entityWidth: 5, entityCount: 3, visualVariant: 1),
                Lane(row: 5, kind: .river, direction: .left,  speed: 0.06, entityWidth: 3, entityCount: 3, visualVariant: 0),
                Lane(row: 6, kind: .river, direction: .right, speed: 0.03, entityWidth: 6, entityCount: 3, visualVariant: 1),
                Lane(row: 7, kind: .river, direction: .left,  speed: 0.07, entityWidth: 3, entityCount: 3, visualVariant: 0),
                Lane(row: 9,  kind: .road, direction: .left,  speed: 0.08, entityWidth: 2, entityCount: 4, visualVariant: 0),
                Lane(row: 10, kind: .road, direction: .right, speed: 0.11, entityWidth: 2, entityCount: 3, visualVariant: 1),
                Lane(row: 11, kind: .road, direction: .left,  speed: 0.06, entityWidth: 3, entityCount: 3, visualVariant: 2),
                Lane(row: 12, kind: .road, direction: .right, speed: 0.09, entityWidth: 2, entityCount: 4, visualVariant: 0),
            ]
        }
        // Spawn entities evenly spaced along each lane.
        entities = lanes.map { lane in
            let spacing = Double(Self.cols) / Double(lane.entityCount)
            return (0..<lane.entityCount).map { i in
                Entity(x: Double(i) * spacing)
            }
        }
    }

    private func respawnFrog() {
        frogX = Self.frogStartCol
        frogY = Self.startRow
        frogPixelX = Double(frogX)
        ridingLane = nil
        ridingEntity = nil
        bestRow = Self.startRow
    }

    // MARK: - Input

    /// One hop per call. Edge-triggered by the view. Moves the frog
    /// one cell in `dir`; gives a small forward-progress score bonus
    /// when moving up.
    public func hop(_ dir: HopDirection) {
        guard phase == .playing else { return }
        let dx: Int, dy: Int
        switch dir {
        case .up:    dx = 0;  dy = -1
        case .down:  dx = 0;  dy =  1
        case .left:  dx = -1; dy =  0
        case .right: dx =  1; dy =  0
        }
        let newX = max(0, min(Self.cols - 1, frogX + dx))
        // Clamp at goalRow on top so the frog can step ONTO the bank
        // (which immediately wins) but never above it.
        let newY = max(Self.goalRow, min(Self.rows - 1, frogY + dy))
        guard newX != frogX || newY != frogY else { return }

        if dy < 0 && newY < bestRow {
            score += 10
            bestRow = newY
        }
        frogX = newX
        frogY = newY
        frogPixelX = Double(newX)
        ridingLane = nil
        ridingEntity = nil

        // Resolve win immediately if we just hopped onto the goal row.
        if frogY <= Self.goalRow {
            win()
            return
        }
        // Check collisions at the new cell (a hop INTO a hazard kills).
        resolveFrogVsLanes(isHopping: true)
    }

    // MARK: - Tick

    public func tick() {
        guard phase == .playing else { return }

        // Tick the per-crossing clock first.
        if timeRemainingTicks > 0 {
            timeRemainingTicks -= 1
        }
        if timeRemainingTicks <= 0 {
            die(.timeUp)
            return
        }

        // Advance hazards.
        advanceEntities()

        // If the frog is riding a log, drift it along with the log.
        // We update `frogPixelX` and re-derive the cell-level `frogX`
        // each frame; if the frog rides off-screen, it's lost.
        if let li = ridingLane, let ei = ridingEntity,
           lanes.indices.contains(li), entities[li].indices.contains(ei) {
            let lane = lanes[li]
            let delta = (lane.direction == .right) ? lane.speed : -lane.speed
            frogPixelX += delta
            frogX = Int(frogPixelX.rounded())
            if frogPixelX < -0.5 || frogPixelX > Double(Self.cols) - 0.5 {
                die(.carriedOff)
                return
            }
        }

        // Re-resolve collisions for the frog's current cell.
        resolveFrogVsLanes(isHopping: false)
    }

    // MARK: - Internals

    private func advanceEntities() {
        for li in lanes.indices {
            let lane = lanes[li]
            let delta = (lane.direction == .right) ? lane.speed : -lane.speed
            // Total wrap span includes the entity's own width so a
            // departing entity wraps when it's fully off-screen rather
            // than the moment its left edge crosses the boundary.
            let span = Double(Self.cols + lane.entityWidth)
            for ei in entities[li].indices {
                entities[li][ei].x += delta
                if entities[li][ei].x > Double(Self.cols) {
                    entities[li][ei].x -= span
                } else if entities[li][ei].x < -Double(lane.entityWidth) {
                    entities[li][ei].x += span
                }
            }
        }
    }

    /// Find which hazard lane (if any) the frog occupies and resolve
    /// the consequences: crushed by a car, drowned in open river, or
    /// safely riding a log.
    ///
    /// `isHopping` distinguishes a fresh hop INTO a cell from the
    /// continuous tick check — useful for future polish (we could
    /// e.g. forgive landing on a log half-on for one tick).
    private func resolveFrogVsLanes(isHopping: Bool) {
        _ = isHopping
        guard let li = lanes.firstIndex(where: { $0.row == frogY }) else {
            // Not in a hazard lane (median, sidewalk, goal). Snap
            // pixel-X back to cell-X — we're not riding anything.
            ridingLane = nil
            ridingEntity = nil
            frogPixelX = Double(frogX)
            return
        }
        let lane = lanes[li]
        let overlap: Int? = entities[li].firstIndex { e in
            // Overlap test: the frog's center sits within the entity's
            // horizontal extent on the cell grid. 0.5-cell tolerances
            // mean a half-on-the-log frog still rides.
            let entityLeft  = e.x - 0.5
            let entityRight = e.x + Double(lane.entityWidth) - 0.5
            return frogPixelX >= entityLeft && frogPixelX <= entityRight
        }
        switch lane.kind {
        case .road:
            if overlap != nil {
                die(.crushed)
                return
            }
            ridingLane = nil
            ridingEntity = nil
        case .river:
            guard let idx = overlap else {
                die(.drowned)
                return
            }
            ridingLane = li
            ridingEntity = idx
        }
    }

    private func die(_ cause: DeathCause) {
        lastDeath = cause
        lives -= 1
        if lives <= 0 {
            phase = .dead
        } else {
            // Brief penalty: knock 50 points off (down to zero floor)
            // and respawn at the start sidewalk.
            score = max(0, score - 50)
            respawnFrog()
        }
    }

    private func win() {
        let timeBonus = timeRemainingTicks / 6     // ~10pt per second left
        let livesBonus = max(0, lives - 1) * 100   // reward unused lives
        score += 500 + timeBonus + livesBonus
        phase = .won
    }
}
