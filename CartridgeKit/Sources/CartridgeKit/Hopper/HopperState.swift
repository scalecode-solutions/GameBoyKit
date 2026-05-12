import Foundation
import Observation
import ConsoleKit

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

    /// Initial timer for Heist mode — slower than Classic since
    /// stealth demands patience.
    public static let heistTimeTicks: Int = 60 * 60

    /// Cells a guard's vision cone extends in front of them.
    public static let heistConeLength: Int = 4

    // MARK: - Types

    /// Which mode the player is currently inside.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        case endless
        case nightShift
        case heist

        public var displayName: String {
            switch self {
            case .classic:    return "CLASSIC"
            case .endless:    return "ENDLESS"
            case .nightShift: return "NIGHT SHIFT"
            case .heist:      return "HEIST"
            }
        }

        public var briefing: String {
            switch self {
            case .classic:    return "ROAD. RIVER. REACH THE TOP."
            case .endless:    return "CLIMB FOREVER. DON'T FALL BEHIND."
            case .nightShift: return "DAY THEN DARK. WATCH THE HEADLIGHTS."
            case .heist:      return "SNEAK PAST GUARDS. DODGE THEIR EYES."
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
        case safe    // no entities; safe grass strip (used in Endless)
        case patrol  // entity = guard (bouncing); standing in vision cone = caught
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

    /// A single car / log / guard in continuous cell-space. `facing`
    /// only matters for patrol guards (it drives the vision cone
    /// direction and bouncing-at-edges behavior); other lane kinds
    /// ignore it.
    public struct Entity: Sendable {
        public var x: Double                  // cell x; can be off-screen for wrap
        public var facing: LaneDirection = .right
    }

    /// Reason the frog died this life. Surfaced to the result banner.
    public enum DeathCause: Sendable, Equatable {
        case crushed       // hit by a car
        case drowned       // in river, not on a log
        case carriedOff    // log rode the frog off the screen
        case timeUp        // Classic / Heist crossing clock hit zero
        case fellBehind    // Endless: scrolled off the screen's bottom
        case spotted       // Heist: caught in a guard's vision cone
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

    /// Whether the just-ended run set a new per-mode best — drives
    /// the "NEW BEST!" flag on the result banner.
    public private(set) var isNewBest: Bool = false

    /// Screen-shake effect — triggered on death (car / drown / cone),
    /// the view reads `offsetX` / `offsetY` and applies them to the
    /// LCD.
    public internal(set) var cameraShake: CameraShake = CameraShake()

    /// Win-celebration particles — sprayed at the frog's position
    /// when it reaches the goal row.
    public internal(set) var particles: ParticleSystem = ParticleSystem()

    /// Cartridge identifier used as the `CartridgeScores` key.
    public static let cartridgeId = "hopper"

    /// All-time best score for `mode` from the shared persistence
    /// store. Zero on fresh install.
    public func bestScore(for mode: Mode) -> Int {
        CartridgeScores.best(cartridge: Self.cartridgeId, mode: mode.rawValue)
    }

    /// Highest row reached (lowest Y value) during the current life —
    /// used by Endless mode scoring; harmless in Classic.
    public private(set) var bestRow: Int = 0

    // Endless-mode state.

    /// World-row of the screen's top edge. Decreases as the camera
    /// scrolls upward to reveal higher world rows. Zero in Classic
    /// (the camera doesn't move). Stored as Double so the camera can
    /// scroll smoothly at fractional cell speeds.
    public private(set) var cameraRow: Double = 0

    /// How many cells per tick the camera moves upward in Endless.
    /// Stored on the model so future polish can ramp this with score.
    public private(set) var endlessScrollRate: Double = 0.012

    /// In Endless mode, the most-negative (highest) world row we've
    /// already generated terrain for. Procgen extends this upward as
    /// the camera approaches it.
    public private(set) var endlessTopRow: Int = 0

    /// Seeded RNG for Endless procgen so tests can pin a deterministic
    /// world. nil in Classic.
    @ObservationIgnored
    private var endlessRng: (any RandomNumberGenerator)? = nil

    @ObservationIgnored
    private var endlessRecentKinds: [LaneKind] = []   // last few generated kinds, for variety bias

    // Night Shift state.

    /// Ticks 0..<nightShiftCycleLen. Day phase is the first half,
    /// night is the second. `isNightPhase` is the computed flag.
    public private(set) var nightShiftCycleTick: Int = 0

    /// Length of one full day+night cycle (ticks). Half is day, half
    /// is night. At 60Hz, 600 ticks = 10s cycle = 5s day / 5s night.
    public static let nightShiftCycleLen: Int = 600

    /// Ticks each phase boundary spends ramping `nightProgress` between
    /// 0 and 1. At 60Hz, 30 ticks = 0.5s fade in / out.
    public static let nightFadeTicks: Int = 30

    /// Speed multiplier applied to lane traffic at full night. Speed
    /// linearly interpolates from 1.0 (day) toward this value as
    /// `nightProgress` rises 0→1, so the transition is smooth.
    public static let nightSpeedMultiplier: Double = 0.65

    /// 0 = full day, 1 = full night. Ramps smoothly across each phase
    /// boundary over `nightFadeTicks`. Drives overlay opacity, traffic
    /// speed, and headlight visibility so the transition feels like a
    /// short dusk/dawn rather than a hard switch.
    public var nightProgress: Double {
        guard mode == .nightShift else { return 0 }
        let len  = Self.nightShiftCycleLen
        let half = len / 2
        let fade = Self.nightFadeTicks
        let t    = nightShiftCycleTick
        if t < half - fade        { return 0 }
        if t < half               { return Double(t - (half - fade)) / Double(fade) }
        if t < len - fade         { return 1 }
        return 1 - Double(t - (len - fade)) / Double(fade)
    }

    public var isNightPhase: Bool {
        nightProgress >= 0.5
    }

    // MARK: - Init

    public init() {
        resetToTitle()
    }

    /// Test seam — lets tests inject a deterministic RNG so Endless
    /// procgen is reproducible. Production callers use `init()`.
    public init<R: RandomNumberGenerator>(endlessRng: R) {
        self.endlessRng = endlessRng
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
        cameraRow = 0
        endlessTopRow = 0
        endlessRecentKinds = []
        nightShiftCycleTick = 0
        setupLanes(for: mode)
        switch mode {
        case .classic, .nightShift:
            // Night Shift uses the same Classic layout, lives, and timer
            // — the day/night cycle drives the visibility + traffic-
            // speed differences, not the lane configuration.
            lives = Self.classicLives
            timeRemainingTicks = Self.classicTimeTicks
        case .endless:
            // Endless is one-shot — die once, run ends. The HUD shows
            // "ROWS X" rather than "TIME XX" while in this mode.
            lives = 1
            timeRemainingTicks = 0
        case .heist:
            // Heist: same 3 lives as Classic but a longer timer
            // because stealth play is slower (waiting for vision
            // cones to pass takes time).
            lives = Self.classicLives
            timeRemainingTicks = Self.heistTimeTicks
        }
        score = 0
        lastDeath = nil
        isNewBest = false
        bestRow = Self.startRow
        particles.clear()
        respawnFrog()
        phase = .playing
    }

    public func retryRun() {
        guard phase == .dead || phase == .won else { return }
        startRun(mode)
    }

    /// Back out to the mode-select grid from a result screen or from
    /// a paused run (B button while paused = "MENU" in the banner).
    public func exitToModeSelect() {
        guard phase == .dead || phase == .won || phase == .paused else { return }
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
        isNewBest = false
        bestRow = 0
        cameraRow = 0
        endlessTopRow = 0
        endlessRecentKinds = []
        nightShiftCycleTick = 0
    }

    // MARK: - Lane setup

    private func setupLanes(for mode: Mode) {
        switch mode {
        case .classic, .nightShift:
            // Night Shift uses the same Classic five-river + median +
            // four-road layout. The night phase's reduced visibility
            // and slower traffic provide the twist, not a different
            // lane configuration.
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
            // Spawn entities evenly spaced along each lane.
            entities = lanes.map { lane in
                let spacing = Double(Self.cols) / Double(lane.entityCount)
                return (0..<lane.entityCount).map { i in
                    Entity(x: Double(i) * spacing)
                }
            }
        case .heist:
            // Heist: four patrol corridors with safe-floor gaps
            // between them. Guards walk back-and-forth (bouncing at
            // lane edges) and project a vision cone in front of them
            // that the frog must avoid. Layout tuned so the player
            // has rhythmic timing windows but isn't trivial.
            //
            //   row 3   patrol — slow, 2 guards, long vision
            //   row 4   safe floor
            //   row 5   patrol — medium, 3 guards
            //   row 6   safe floor
            //   row 7   patrol — fast, 2 guards
            //   row 8   safe floor
            //   row 9   patrol — slow, 2 guards
            //   rows 10-17 lobby/start area
            lanes = [
                Lane(row: 3, kind: .patrol, direction: .right, speed: 0.04,
                     entityWidth: 1, entityCount: 2, visualVariant: 0),
                Lane(row: 5, kind: .patrol, direction: .left,  speed: 0.07,
                     entityWidth: 1, entityCount: 3, visualVariant: 1),
                Lane(row: 7, kind: .patrol, direction: .right, speed: 0.10,
                     entityWidth: 1, entityCount: 2, visualVariant: 0),
                Lane(row: 9, kind: .patrol, direction: .left,  speed: 0.05,
                     entityWidth: 1, entityCount: 2, visualVariant: 1),
            ]
            // Spawn guards evenly along each lane, all initially facing
            // the lane's direction. They'll bounce at edges each tick.
            entities = lanes.map { lane in
                let spacing = Double(Self.cols) / Double(lane.entityCount + 1)
                return (0..<lane.entityCount).map { i in
                    Entity(x: spacing * Double(i + 1),
                           facing: lane.direction)
                }
            }

        case .endless:
            // Endless: every world row gets a Lane entry (rendered as
            // its own terrain strip). Pre-fill the initial viewport
            // plus a buffer above (negative rows) so the camera has
            // procgen-ready land to scroll into.
            //
            // Rows around the frog's spawn position are forced to .safe
            // so the player doesn't immediately die.
            lanes = []
            entities = []
            endlessTopRow = Self.rows + 2    // start below the visible area, grow upward
            endlessRecentKinds = []
            // First: lay down the visible starting area (rows -8 ... rows+2).
            // The frog spawns at startRow (=16) on guaranteed-safe ground.
            for row in stride(from: Self.rows + 1, through: -8, by: -1) {
                let forced: LaneKind? = {
                    // Force the spawn row + a 1-row buffer above and
                    // below to .safe so the player has somewhere to
                    // stand before the world starts demanding hops.
                    if abs(row - Self.startRow) <= 1 { return .safe }
                    if row >= Self.rows { return .safe }    // sidewalk under spawn
                    return nil
                }()
                appendEndlessLane(at: row, forced: forced)
            }
            endlessTopRow = -8
        }
    }

    /// Generate (or extend) Endless lanes until at least `targetTopRow`
    /// (most-negative row) is in the lanes array. Lanes are appended
    /// to the end of the array regardless of their row — collision
    /// lookups use `firstIndex(where: { $0.row == frogY })`.
    private func ensureEndlessLanes(throughRow targetTopRow: Int) {
        while endlessTopRow > targetTopRow {
            endlessTopRow -= 1
            appendEndlessLane(at: endlessTopRow, forced: nil)
        }
    }

    private func appendEndlessLane(at row: Int, forced: LaneKind?) {
        let kind = forced ?? pickEndlessLaneKind()
        let lane = makeEndlessLane(row: row, kind: kind)
        lanes.append(lane)
        entities.append(spawnEntities(for: lane))
        endlessRecentKinds.append(kind)
        if endlessRecentKinds.count > 3 {
            endlessRecentKinds.removeFirst()
        }
    }

    /// Pick a lane kind with a small variety bias: if the last two
    /// generated kinds were the same, force something different so we
    /// don't get runs of 4+ identical lanes in a row.
    private func pickEndlessLaneKind() -> LaneKind {
        let r = rngDouble()
        let lastTwoSame =
            endlessRecentKinds.count >= 2 &&
            endlessRecentKinds[endlessRecentKinds.count - 1] ==
            endlessRecentKinds[endlessRecentKinds.count - 2]

        // Base weights: ~35% road, ~35% river, ~30% safe.
        // (Safe lanes give the player breathing room between hazards.)
        let kind: LaneKind = {
            if r < 0.35 { return .road }
            if r < 0.70 { return .river }
            return .safe
        }()

        if lastTwoSame && endlessRecentKinds.last == kind {
            // Force a switch — pick anything but the repeated kind.
            let alternatives: [LaneKind] = [.road, .river, .safe].filter { $0 != kind }
            return alternatives[Int(rngDouble() * Double(alternatives.count))]
        }
        return kind
    }

    private func makeEndlessLane(row: Int, kind: LaneKind) -> Lane {
        switch kind {
        case .safe, .patrol:
            // .patrol is never picked by `pickEndlessLaneKind` —
            // listing it here keeps the switch exhaustive and falls
            // back to a safe lane if someone ever wires it in.
            return Lane(row: row, kind: .safe,
                        direction: .left, speed: 0,
                        entityWidth: 0, entityCount: 0,
                        visualVariant: 0)
        case .road:
            let dir: LaneDirection = rngDouble() < 0.5 ? .left : .right
            // Speed range: 0.05 (slow) to 0.13 (fast)
            let speed = 0.05 + rngDouble() * 0.08
            let variant = Int(rngDouble() * 3)
            let width = (variant == 2) ? 3 : 2      // variant 2 = trucks
            let count = Int(2 + rngDouble() * 3)    // 2-4 cars
            return Lane(row: row, kind: .road,
                        direction: dir, speed: speed,
                        entityWidth: width, entityCount: count,
                        visualVariant: variant)
        case .river:
            let dir: LaneDirection = rngDouble() < 0.5 ? .left : .right
            let speed = 0.03 + rngDouble() * 0.05   // 0.03 to 0.08
            let variant = Int(rngDouble() * 2)
            let width = Int(3 + rngDouble() * 4)    // 3-6 wide logs
            let count = Int(2 + rngDouble() * 2)    // 2-3 logs
            return Lane(row: row, kind: .river,
                        direction: dir, speed: speed,
                        entityWidth: width, entityCount: count,
                        visualVariant: variant)
        }
    }

    private func spawnEntities(for lane: Lane) -> [Entity] {
        guard lane.entityCount > 0 else { return [] }
        let spacing = Double(Self.cols) / Double(lane.entityCount)
        // Slight random phase per lane so adjacent lanes don't all
        // line up at x=0 on spawn.
        let phase = rngDouble() * spacing
        return (0..<lane.entityCount).map { i in
            Entity(x: Double(i) * spacing + phase)
        }
    }

    /// Return a uniform random Double in [0, 1). Uses the seeded RNG
    /// when one was injected (tests), otherwise falls back to the
    /// system RNG so each run is fresh.
    private func rngDouble() -> Double {
        if endlessRng != nil {
            return Double.random(in: 0..<1, using: &endlessRng!)
        } else {
            return Double.random(in: 0..<1)
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
        // Top clamp depends on mode:
        // - Classic: clamp at goalRow so the frog can step ONTO the
        //   bank (which immediately wins) but never above it.
        // - Endless: no upward clamp — keep climbing into procgen.
        let newY: Int = {
            switch mode {
            case .classic, .nightShift, .heist:
                return max(Self.goalRow, min(Self.rows - 1, frogY + dy))
            case .endless:
                // Always extend procgen ahead before we let the frog
                // leap into it, so the new row already has terrain.
                let candidate = min(Self.rows - 1, frogY + dy)
                if candidate < endlessTopRow {
                    ensureEndlessLanes(throughRow: candidate - 4)
                }
                return candidate
            }
        }()
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

        // Classic / Night Shift / Heist: reaching the goal row
        // immediately wins. Endless has no win condition — keep climbing.
        if mode != .endless && frogY <= Self.goalRow {
            win()
            return
        }
        // Heist: hopping INTO a vision cone is just as fatal as standing
        // in one — check before falling through to lane collision.
        if mode == .heist && isFrogSpotted() {
            die(.spotted)
            return
        }
        // Check collisions at the new cell (a hop INTO a hazard kills).
        resolveFrogVsLanes(isHopping: true)
    }

    // MARK: - Tick

    public func tick() {
        // Effects tick regardless of phase so a death's screen shake
        // or a win's particle burst completes even after the result
        // banner appears.
        cameraShake.tick()
        particles.tick()
        guard phase == .playing else { return }
        switch mode {
        case .classic:    classicTick()
        case .endless:    endlessTick()
        case .nightShift: nightShiftTick()
        case .heist:      heistTick()
        }
    }

    // MARK: - Classic mode tick

    private func classicTick() {
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

        resolveFrogVsLanes(isHopping: false)
    }

    // MARK: - Endless mode tick

    /// Crossy-Road-style endless ascent. Camera scrolls upward at a
    /// constant rate; new procedurally-generated lanes appear above
    /// the camera as needed. The frog must keep climbing or it'll
    /// scroll off the bottom of the screen.
    private func endlessTick() {
        // Scroll camera up by scrollRate (cameraRow becomes more negative).
        cameraRow -= endlessScrollRate

        // Procgen: ensure we have lanes far enough above the camera
        // for the upper screen + some buffer.
        ensureEndlessLanes(throughRow: Int(cameraRow.rounded()) - 4)

        advanceEntities()

        // Log-ride drift.
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

        // Fall-behind check: if the frog's screen-row exceeds the
        // viewport's bottom, it's been left behind.
        let screenRow = Double(frogY) - cameraRow
        if screenRow > Double(Self.rows - 1) + 0.5 {
            die(.fellBehind)
            return
        }

        resolveFrogVsLanes(isHopping: false)
    }

    // MARK: - Night Shift mode tick

    /// Night Shift: Classic crossing but with a 10-second day/night
    /// cycle. The visibility is hard-flipped at the half-cycle mark
    /// (the view dims everything outside a lantern zone around the
    /// frog and adds car headlights). Traffic slows to 65% normal
    /// speed during the night phase so the player has a chance to
    /// push when the lights drop.
    private func nightShiftTick() {
        // Advance the cycle counter (wraps at the cycle length).
        nightShiftCycleTick = (nightShiftCycleTick + 1) % Self.nightShiftCycleLen

        // Tick the per-crossing clock (same as Classic).
        if timeRemainingTicks > 0 {
            timeRemainingTicks -= 1
        }
        if timeRemainingTicks <= 0 {
            die(.timeUp)
            return
        }

        // Smooth speed interpolation: day (1.0) → night (0.65) and back
        // tracks `nightProgress` so traffic glides between phases.
        let p = nightProgress
        let multiplier = 1.0 - (1.0 - Self.nightSpeedMultiplier) * p
        advanceEntities(speedMultiplier: multiplier)

        // Log-ride drift, with the same smoothly-interpolated multiplier.
        if let li = ridingLane, let ei = ridingEntity,
           lanes.indices.contains(li), entities[li].indices.contains(ei) {
            let lane = lanes[li]
            let delta = ((lane.direction == .right) ? lane.speed : -lane.speed) * multiplier
            frogPixelX += delta
            frogX = Int(frogPixelX.rounded())
            if frogPixelX < -0.5 || frogPixelX > Double(Self.cols) - 0.5 {
                die(.carriedOff)
                return
            }
        }

        resolveFrogVsLanes(isHopping: false)
    }

    // MARK: - Heist mode tick

    /// Heist: guards walk back-and-forth along their patrol lanes
    /// (bouncing off the edges) and project a vision cone in front
    /// of them. Frog standing in any cone — or on a guard's tile — is
    /// caught (.spotted). 60-second timer; Classic 3-lives respawn.
    private func heistTick() {
        // Crossing clock.
        if timeRemainingTicks > 0 {
            timeRemainingTicks -= 1
        }
        if timeRemainingTicks <= 0 {
            die(.timeUp)
            return
        }

        // Advance guards: each entity steps in its own facing direction
        // (not the lane.direction) so guards can bounce independently.
        // Lane edges flip the facing flag and clamp position.
        for li in lanes.indices where lanes[li].kind == .patrol {
            let lane = lanes[li]
            for ei in entities[li].indices {
                let dir = (entities[li][ei].facing == .right) ? 1.0 : -1.0
                entities[li][ei].x += dir * lane.speed
                let leftEdge: Double  = 0
                let rightEdge: Double = Double(Self.cols - 1)
                if entities[li][ei].x <= leftEdge {
                    entities[li][ei].x = leftEdge
                    entities[li][ei].facing = .right
                } else if entities[li][ei].x >= rightEdge {
                    entities[li][ei].x = rightEdge
                    entities[li][ei].facing = .left
                }
            }
        }

        // Vision check: is the frog inside any guard's cone?
        if isFrogSpotted() {
            die(.spotted)
            return
        }
    }

    /// Returns true if the frog is currently in any patrol guard's
    /// vision cone — or standing on a guard's tile (point-blank).
    /// Vision cone: heistConeLength cells in the guard's facing
    /// direction, on the guard's lane row only.
    public func isFrogSpotted() -> Bool {
        guard mode == .heist else { return false }
        let fX = frogX, fY = frogY
        for (li, lane) in lanes.enumerated() where lane.kind == .patrol {
            if fY != lane.row { continue }
            for entity in entities[li] {
                let gx = Int(entity.x.rounded())
                if gx == fX { return true }
                if entity.facing == .right {
                    if fX > gx && fX - gx <= Self.heistConeLength { return true }
                } else {
                    if gx > fX && gx - fX <= Self.heistConeLength { return true }
                }
            }
        }
        return false
    }

    // MARK: - Internals

    private func advanceEntities(speedMultiplier: Double = 1.0) {
        for li in lanes.indices {
            let lane = lanes[li]
            let baseDelta = (lane.direction == .right) ? lane.speed : -lane.speed
            let delta = baseDelta * speedMultiplier
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
        case .safe:
            // No hazards on a safe lane; just snap pixel-X back to the
            // cell grid so we don't carry over log-ride drift.
            ridingLane = nil
            ridingEntity = nil
            frogPixelX = Double(frogX)
        case .patrol:
            // Vision-cone spotting is handled by `heistTick` /
            // `isFrogSpotted`; this helper just doesn't ride patrols.
            ridingLane = nil
            ridingEntity = nil
            frogPixelX = Double(frogX)
        }
    }

    /// Persist `score` as the new per-mode best if it exceeds the
    /// stored value, and set `isNewBest` for the result banner.
    private func recordCurrentScore() {
        isNewBest = CartridgeScores.recordIfBetter(
            score, cartridge: Self.cartridgeId, mode: mode.rawValue
        )
    }

    private func die(_ cause: DeathCause) {
        lastDeath = cause
        lives -= 1
        // Every death (fatal or respawn) shakes the screen — sells
        // the hit. Cone-spot deaths shake a bit less than physical
        // car/drown hits since they're surveillance-y, not crunchy.
        let amplitude: Double = (cause == .spotted) ? 2.0 : 3.0
        cameraShake.trigger(amplitude: amplitude, ticks: 12)
        if lives <= 0 {
            phase = .dead
            recordCurrentScore()
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
        recordCurrentScore()
        // Celebration burst at the frog's pixel position — happens
        // on the lily pad row so the particles fan out from the bank.
        let cs = Double(Self.cellSize)
        particles.burst(
            at: (x: frogPixelX * cs + cs / 2, y: Double(frogY) * cs + cs / 2),
            count: 16,
            speedRange: 0.8...2.2,
            lifeRange: 22...36,
            upwardBias: 0.8
        )
    }
}
