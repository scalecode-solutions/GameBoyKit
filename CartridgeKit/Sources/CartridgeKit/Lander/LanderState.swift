import Foundation
import Observation
import ConsoleKit

/// Game state for the Lander cartridge. Pure model — no SwiftUI
/// types — so it's straightforward to unit-test.
///
/// The cartridge will host multiple modes (Classic, Pendulum, Mail
/// Run, Cave Dive) — Classic is the only one wired up in v1. The
/// `Mode` enum + mode-select phase machinery is here so additional
/// modes plug in as new cases + per-mode game logic without
/// reshuffling the architecture.
@MainActor
@Observable
public final class LanderState {

    // MARK: - Geometry (256×144 logical LCD)

    public static let lcdWidth:  Int = 256
    public static let lcdHeight: Int = 144

    /// Top HUD strip — fuel gauge + velocity readout live here.
    public static let hudHeight: Int = 18

    /// Top of the ground baseline (everything below is dirt).
    public static let groundY: Int = 132

    /// A landing pad's geometry. Pads are top-aligned (cargo / ship
    /// rests on `top`, legs descend to `groundY`).
    public struct Pad: Sendable, Equatable {
        public let left:  Int
        public let right: Int      // exclusive
        public let top:   Int
        public var width: Int { right - left }
    }

    /// Single landing pad used by Classic + Pendulum modes.
    public static let classicPad = Pad(left: 168, right: 196, top: 116)

    /// Three pads for Mail Run mode — left low, middle raised, right
    /// low. Variable heights so the player has to climb between drops.
    public static let mailRunPads: [Pad] = [
        Pad(left: 16,  right: 44,  top: 122),    // 1: ground level, far left
        Pad(left: 112, right: 144, top: 86),     // 2: high middle (rooftop)
        Pad(left: 212, right: 240, top: 122)     // 3: ground level, far right
    ]

    /// Cave depth (in logical pixels) for Cave Dive mode. The ship
    /// descends through this much vertical space; camera follows.
    /// ~6.7 screen-heights — long enough that the journey has pacing
    /// (relaxed entry → first squeeze → breath → tight middle → wide
    /// chamber → winding final approach → bottom chamber landing).
    public static let caveDepth: Int = 960

    /// Landing pad at the bottom of the cave. Sits inside the widened
    /// bottom chamber so the player has a comfortable target.
    public static let caveDivePad = Pad(left: 110, right: 150, top: caveDepth - 14)

    // Back-compat shims for older references to the single Classic pad.
    // New rendering code should iterate `pads` and use `currentTargetPad`.
    public static var padLeft:  Int { classicPad.left }
    public static var padRight: Int { classicPad.right }
    public static var padTop:   Int { classicPad.top }
    public static var padWidth: Int { classicPad.width }

    // MARK: - Types

    /// Which mode the player is currently inside.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        case pendulum
        case mailRun
        case caveDive

        public var displayName: String {
            switch self {
            case .classic:  return "CLASSIC"
            case .pendulum: return "PENDULUM"
            case .mailRun:  return "MAIL RUN"
            case .caveDive: return "CAVE DIVE"
            }
        }

        public var briefing: String {
            switch self {
            case .classic:  return "LAND ON THE PAD. SOFT TOUCH."
            case .pendulum: return "CARGO ON A TETHER. NO WHIPPING."
            case .mailRun:  return "DELIVER TO ALL PADS. BEAT THE CLOCK."
            case .caveDive: return "DESCEND THE CAVE. AVOID THE WALLS."
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case title
        case modeSelect
        case playing
        case paused
        case landed
        case crashed
    }

    // MARK: - State

    public private(set) var phase: Phase = .title
    public private(set) var mode: Mode = .classic
    public private(set) var modeSelectCursor: Int = 0      // index into Mode.allCases

    // Ship physics (shared across all modes — units are logical LCD pixels per tick).
    public private(set) var shipX: Double = 0
    public private(set) var shipY: Double = 0
    public private(set) var vx: Double = 0
    public private(set) var vy: Double = 0
    public private(set) var fuel: Double = 100             // 0…100

    // Last-frame input (for render: flame on, lateral tilt, …)
    public private(set) var thrustingMain: Bool = false
    public private(set) var thrustingLateral: Int = 0      // -1 / 0 / +1

    // Pendulum-mode state — radians measured from straight-down, so
    // theta=0 means the cargo hangs directly beneath the ship, positive
    // theta swings the cargo to the right.
    public private(set) var theta: Double = 0
    public private(set) var thetaDot: Double = 0
    public private(set) var tetherSnapped: Bool = false

    // Mail Run state — sequence of pads to land at, which one is the
    // current target, and the per-mission clock. Index advances on
    // each successful soft landing; mission ends when all pads cleared
    // or the clock hits zero.
    public private(set) var mailRunIndex: Int = 0
    public private(set) var mailRunCleared: [Bool] = []
    public private(set) var timeRemainingTicks: Int = 0

    // Cave Dive state — the two wall arrays (one entry per pixel of
    // depth) plus the current camera Y offset for the scrolling viewport.
    // Walls are generated at the start of each run so each dive has its
    // own seed.
    public private(set) var caveLeftWall:  [Int] = []
    public private(set) var caveRightWall: [Int] = []
    public private(set) var cameraY: Int = 0

    // Result data
    public private(set) var score: Int = 0
    public private(set) var landingImpact: Double = 0      // |vy| at touchdown

    /// Whether the just-ended run set a new per-mode best — surfaced
    /// on the result banner as "NEW BEST!".
    public private(set) var isNewBest: Bool = false

    /// Screen-shake effect — triggered on crashes; the view reads
    /// `offsetX` / `offsetY` and applies them to the LCD.
    public internal(set) var cameraShake: CameraShake = CameraShake()

    /// Cartridge identifier used as the `CartridgeScores` key.
    public static let cartridgeId = "lander"

    /// All-time best score for `mode` from the shared persistence
    /// store. Zero on fresh install.
    public func bestScore(for mode: Mode) -> Int {
        CartridgeScores.best(cartridge: Self.cartridgeId, mode: mode.rawValue)
    }

    // MARK: - Tunables

    /// Tuning constants live as instance properties (private) so different
    /// modes can override them in future via subclass / strategy without
    /// shipping a refactor today.
    private let gravity:           Double = 0.024
    private let thrustAccelMain:   Double = 0.068
    private let thrustAccelSide:   Double = 0.038
    private let fuelBurnMain:      Double = 0.32
    private let fuelBurnSide:      Double = 0.18
    private let landMaxVY:         Double = 0.80     // looser than the original 0.55
    private let landMaxVX:         Double = 0.45     // looser than the original 0.32
    private let ceilingBounceDamp: Double = 0.30

    // Pendulum mode tunables.
    public static let tetherLength: Double = 18
    public static let cargoHalfW:   Double = 3
    public static let cargoHalfH:   Double = 3
    // Pendulum tuning: with thrustAccelSide=0.038 and tetherLength=18,
    // sustained one-direction input drives angular accel ≈ 0.00211 per
    // tick. With damping=0.015 the equilibrium |θ̇| is ~0.141 — well
    // below the snap threshold, so the player can hold lateral without
    // accidental snaps. Snap is reached primarily via the "whip"
    // impulse below: each rapid direction reversal kicks θ̇ tangentially.
    // ~3 quick reversals build past 0.20 and snap the tether.
    private let pendulumDamping:    Double = 0.015
    private let snapAngularRate:    Double = 0.20
    private let whipImpulse:        Double = 0.08    // θ̇ kick on each lateral direction reversal

    // MARK: - Derived state (for HUD feedback + cargo rendering)

    /// True when the ship's current velocity components would qualify
    /// as a soft landing if it touched the pad *right now*. Drives the
    /// in-HUD "SAFE" indicator so the player gets continuous skill
    /// feedback (independent of horizontal alignment with the pad).
    ///
    /// In Pendulum mode this uses the CARGO's velocity, not the ship's
    /// — because the cargo is what touches down.
    public var landingWouldBeSafe: Bool {
        switch mode {
        case .classic, .mailRun, .caveDive:
            return abs(vy) <= landMaxVY && abs(vx) <= landMaxVX
        case .pendulum:
            return !tetherSnapped
                && abs(cargoVY) <= landMaxVY
                && abs(cargoVX) <= landMaxVX
        }
    }

    /// The vy threshold the HUD treats as "too fast" — public so the
    /// view can flash the readout when the player exceeds it.
    public var landingMaxVY: Double { landMaxVY }

    // MARK: - Pendulum derived geometry

    /// Cargo X in logical LCD pixels. Pivot is the ship.
    public var cargoX: Double { shipX + Self.tetherLength * sin(theta) }
    /// Cargo Y in logical LCD pixels. Pivot is the ship.
    public var cargoY: Double { shipY + Self.tetherLength * cos(theta) }
    /// Cargo VX (velocity of bob = pivot velocity + angular contribution).
    public var cargoVX: Double { vx + Self.tetherLength * cos(theta) * thetaDot }
    /// Cargo VY (velocity of bob).
    public var cargoVY: Double { vy - Self.tetherLength * sin(theta) * thetaDot }

    // MARK: - Pads (per-mode)

    /// All pads visible during the current run. Classic + Pendulum use
    /// a single pad; Mail Run uses three at varying heights; Cave Dive
    /// uses a single pad at the bottom of the cave.
    public var pads: [Pad] {
        switch mode {
        case .classic, .pendulum: return [Self.classicPad]
        case .mailRun:            return Self.mailRunPads
        case .caveDive:           return [Self.caveDivePad]
        }
    }

    /// The pad the player is currently trying to land on. For single-pad
    /// modes this is just `pads[0]`; for Mail Run it's whichever pad
    /// the sequence is up to.
    public var currentTargetPad: Pad {
        let pads = self.pads
        let idx = min(max(0, mailRunIndex), pads.count - 1)
        return pads[idx]
    }

    // MARK: - Init

    public init() {
        resetToTitle()
    }

    // MARK: - Phase transitions

    /// From title screen → mode select grid.
    public func openModeSelect() {
        guard phase == .title else { return }
        phase = .modeSelect
        modeSelectCursor = 0
    }

    /// From mode select → title.
    public func returnToTitle() {
        phase = .title
    }

    /// Move the mode-select cursor by delta, wrapping inside the
    /// implemented-modes range. (Currently a no-op since only one
    /// mode exists — kept here so the navigation code is in place
    /// when more modes ship.)
    public func moveModeSelectCursor(_ delta: Int) {
        guard phase == .modeSelect else { return }
        let n = Mode.allCases.count
        modeSelectCursor = ((modeSelectCursor + delta) % n + n) % n
    }

    /// Confirm the highlighted mode and begin a run.
    public func confirmModeSelection() {
        guard phase == .modeSelect else { return }
        let modes = Mode.allCases
        guard modes.indices.contains(modeSelectCursor) else { return }
        startRun(modes[modeSelectCursor])
    }

    /// Begin a fresh run of the given mode.
    public func startRun(_ mode: Mode) {
        self.mode = mode
        // Cave Dive starts the ship at the top of the cave (world Y=8)
        // centered horizontally. Other modes start in the upper-left
        // of the screen with the existing nudge.
        if mode == .caveDive {
            shipX = Double(Self.lcdWidth) * 0.5
            shipY = 8
        } else {
            shipX = Double(Self.lcdWidth) * 0.18
            shipY = Double(Self.hudHeight) + 6
        }
        vx = 0                                          // no starting drift — let the player orient first
        vy = 0
        fuel = 100
        score = 0
        landingImpact = 0
        isNewBest = false
        thrustingMain = false
        thrustingLateral = 0
        // Pendulum: cargo hangs at rest directly below the ship.
        theta = 0
        thetaDot = 0
        tetherSnapped = false
        // Mail Run: reset to first pad, full clock.
        mailRunIndex = 0
        mailRunCleared = Array(repeating: false, count: pads.count)
        timeRemainingTicks = (mode == .mailRun) ? 60 * 60 : 0   // 60s @ 60Hz
        // Cave Dive: generate a fresh procedural cave and reset camera.
        if mode == .caveDive {
            generateCave()
            cameraY = 0
        } else {
            caveLeftWall = []
            caveRightWall = []
            cameraY = 0
        }
        phase = .playing
    }

    /// Generates a fresh procedural cave for Cave Dive mode. The
    /// vertical descent is paced through seven width segments —
    /// alternating tight passages and wide chambers — so the run has
    /// rhythm rather than just "narrow → wider". Two independent sine
    /// stacks drive the left and right walls separately, giving each
    /// side its own organic undulation (the cave doesn't look like a
    /// symmetric tube).
    ///
    /// Per-run randomness comes from four independent phase offsets
    /// (uniform in [0, 2π)) applied to the centerline and per-side
    /// wobble sines. Amplitudes + frequencies stay fixed so the wall-
    /// bounds + minimum-passage-width guarantees are preserved — only
    /// the wave starting points change run-to-run.
    private func generateCave() {
        let depth = Self.caveDepth
        let centerBase = Double(Self.lcdWidth) / 2
        var left  = [Int](); left.reserveCapacity(depth)
        var right = [Int](); right.reserveCapacity(depth)

        // Per-run sine phase offsets. Each run gets a fresh seed, so
        // the cave's curve pattern differs while the gameplay-tuned
        // width profile + amplitudes are preserved.
        let twoPi = Double.pi * 2
        let phaseCenterA = Double.random(in: 0..<twoPi)
        let phaseCenterB = Double.random(in: 0..<twoPi)
        let phaseLeftA   = Double.random(in: 0..<twoPi)
        let phaseLeftB   = Double.random(in: 0..<twoPi)
        let phaseRightA  = Double.random(in: 0..<twoPi)
        let phaseRightB  = Double.random(in: 0..<twoPi)

        for y in 0..<depth {
            // Piecewise width — seven segments tuned for pacing:
            //   0..120     open entry (wide, relaxed)
            //   120..240   first narrowing
            //   240..340   first squeeze (tight)
            //   340..460   relief chamber (wide breath)
            //   460..600   second narrowing into the tight middle
            //   600..720   tight middle (peak difficulty)
            //   720..820   widening
            //   820..900   winding approach
            //   900..960   bottom landing chamber
            let halfWidth: Double = {
                switch y {
                case 0..<120:    return 105                                          // wide mouth
                case 120..<240:  return lerp(105, 52, t: Double(y - 120) / 120)     // narrowing
                case 240..<340:  return 52                                           // first squeeze
                case 340..<460:  return lerp(52, 90, t: Double(y - 340) / 120)      // breath
                case 460..<600:  return lerp(90, 38, t: Double(y - 460) / 140)      // tightening
                case 600..<720:  return 38                                           // tight middle
                case 720..<820:  return lerp(38, 60, t: Double(y - 720) / 100)      // widening
                case 820..<900:  return 55                                           // winding approach
                default:         return 80                                           // bottom chamber
                }
            }()

            // Independent left/right wall undulation — both walls share
            // a slow drifting centerline, but each side also has its
            // own faster wobble so the cave breathes asymmetrically.
            // Random per-run phase offsets vary the curves between
            // runs without changing the amplitude budget.
            let yd = Double(y)
            let centerDrift = sin(yd * 0.020 + phaseCenterA) * 14
                            + sin(yd * 0.041 + phaseCenterB) * 6
            let center = centerBase + centerDrift

            // Per-side wobble adds bulges and constrictions independent
            // of the centerline drift — gives knots and bumps in the
            // walls without crossing the half-width budget.
            let leftWobble  = sin(yd * 0.063 + phaseLeftA) * 5
                            + sin(yd * 0.110 + phaseLeftB) * 3
            let rightWobble = sin(yd * 0.058 + phaseRightA) * 5
                            + sin(yd * 0.135 + phaseRightB) * 3

            left.append(  Int((center - halfWidth + leftWobble).rounded()) )
            right.append( Int((center + halfWidth + rightWobble).rounded()) )
        }
        caveLeftWall  = left
        caveRightWall = right
    }

    /// Linear interpolation helper.
    private func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }

    /// After a result screen, retry the same mode.
    public func retryRun() {
        guard phase == .landed || phase == .crashed else { return }
        startRun(mode)
    }

    /// Back out to the mode-select grid from a result screen or from
    /// a paused run (B button while paused = "MENU" in the banner).
    public func exitToModeSelect() {
        guard phase == .landed || phase == .crashed || phase == .paused else { return }
        phase = .modeSelect
    }

    /// Pause toggle. No-op outside of an active run.
    public func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default:       break
        }
    }

    /// Hard-reset to the title screen. Used by the cartridge on first
    /// mount and would be wired to a "return to library" cleanup if
    /// the player exits mid-run.
    public func resetToTitle() {
        phase = .title
        mode = .classic
        modeSelectCursor = 0
        shipX = 0
        shipY = 0
        vx = 0
        vy = 0
        fuel = 100
        score = 0
        landingImpact = 0
        isNewBest = false
        thrustingMain = false
        thrustingLateral = 0
    }

    // MARK: - Input application (called by the view's tick loop)

    /// Tells the model whether main thrust and/or lateral thrust are
    /// currently held. The model gates them on fuel; render code can
    /// trust `thrustingMain` / `thrustingLateral` reflect actually-firing
    /// thrusters (not just inputs held).
    ///
    /// In Pendulum mode, a rapid reversal of lateral input (left→right
    /// or right→left in successive frames) adds a tangential "whip"
    /// impulse to the pendulum — the mechanism by which players
    /// over-aggressive on the stick can snap the tether.
    public func applyInput(mainThrust: Bool, lateral: Int) {
        let prevLateral = thrustingLateral
        let mainActive = mainThrust && fuel > 0
        let sideActive = lateral != 0 && fuel > 0
        let newSide = sideActive ? lateral : 0

        // Whip impulse: only on a true reversal (prev != 0, new != 0,
        // and they point in opposite directions). Releasing and
        // re-pressing the same direction doesn't whip; flipping does.
        //
        // The impulse adds to the CURRENT swing direction (not the
        // input direction) — so rapid back-and-forth compounds the
        // swing magnitude instead of canceling it. Physically loose
        // (a real reversal would push the bob in the opposite of the
        // ship's new motion), but the game-feel goal is "bashing the
        // stick whips the cargo." 3–4 quick reversals build past the
        // snap threshold.
        if mode == .pendulum
            && phase == .playing
            && prevLateral != 0
            && newSide != 0
            && prevLateral != newSide {
            let swingSign: Double = thetaDot >= 0 ? 1.0 : -1.0
            thetaDot += swingSign * whipImpulse * cos(theta)
        }

        thrustingMain = mainActive
        thrustingLateral = newSide
    }

    // MARK: - Tick

    /// Advance one physics step. The view calls this at ~60Hz every
    /// frame — screen-shake effects advance regardless of phase so a
    /// crash's shake completes even after the result banner appears.
    /// Physics dispatch only fires while `.playing`.
    public func tick() {
        cameraShake.tick()
        guard phase == .playing else { return }
        switch mode {
        case .classic:  classicTick()
        case .pendulum: pendulumTick()
        case .mailRun:  mailRunTick()
        case .caveDive: caveDiveTick()
        }
    }

    // MARK: - Shared ship physics step

    /// Burn fuel, apply gravity + thrust, integrate ship position, and
    /// handle horizontal wraparound + ceiling bounce. Used by both
    /// Classic and Pendulum modes — they differ only in their landing
    /// condition, not in how the ship itself moves.
    private func stepShipPhysics() {
        // Latch whether each thruster *actually fires* this frame. We
        // gate on fuel > 0 BEFORE the burn so the very last frame of
        // fuel still gets its boost — feels generous, not stingy.
        let mainBurns = thrustingMain && fuel > 0
        let sideBurns = thrustingLateral != 0 && fuel > 0
        if mainBurns { fuel = max(0, fuel - fuelBurnMain) }
        if sideBurns { fuel = max(0, fuel - fuelBurnSide) }

        vy += gravity
        if mainBurns { vy -= thrustAccelMain }
        if sideBurns { vx += Double(thrustingLateral) * thrustAccelSide }

        if fuel <= 0 {
            thrustingMain = false
            thrustingLateral = 0
        }

        // Integrate
        shipX += vx
        shipY += vy

        // Horizontal wrap — the moon's edge is just the other edge.
        // Keeps the playfield endlessly explorable without "off-screen
        // death by drift," which feels punishing for a physics game.
        if shipX < 0 {
            shipX += Double(Self.lcdWidth)
        } else if shipX >= Double(Self.lcdWidth) {
            shipX -= Double(Self.lcdWidth)
        }

        // Ceiling — bounce off the bottom of the HUD with damping.
        let ceiling = Double(Self.hudHeight) + 4
        if shipY < ceiling {
            shipY = ceiling
            vy = abs(vy) * ceilingBounceDamp
        }
    }

    // MARK: - Classic mode tick

    private func classicTick() {
        stepShipPhysics()

        let pad = currentTargetPad
        // Ground / pad contact check — uses ship body
        let shipBottom = shipY + 6                 // ship is ~12 tall, half = 6
        if shipBottom >= Double(pad.top) {
            let halfWidth: Double = 6              // ship is ~12 wide
            let shipLeft  = shipX - halfWidth
            let shipRight = shipX + halfWidth
            let onPad = shipLeft >= Double(pad.left)
                     && shipRight <= Double(pad.right)
                     && shipBottom <= Double(pad.top) + 2

            if onPad {
                resolveClassicLanding(pad: pad)
                return
            }
        }
        if shipBottom >= Double(Self.groundY) {
            crash(impact: abs(vy))
        }
    }

    private func resolveClassicLanding(pad: Pad) {
        let softVertical   = abs(vy) <= landMaxVY
        let softHorizontal = abs(vx) <= landMaxVX
        landingImpact = abs(vy)
        if softVertical && softHorizontal {
            shipY = Double(pad.top) - 6
            vx = 0
            vy = 0
            score = 1000 + Int(fuel * 10) + max(0, Int((landMaxVY - landingImpact) * 800))
            phase = .landed
            recordCurrentScore()
        } else {
            crash(impact: abs(vy))
        }
    }

    // MARK: - Pendulum mode tick

    /// Pendulum mode physics: ship moves as in Classic, but a tethered
    /// cargo dangles below. The cargo is what has to land softly on
    /// the pad — the ship hovers above while the player damps the swing
    /// and lowers the cargo onto target.
    ///
    /// Pendulum dynamics: standard pendulum restoring force
    /// (`θ̈ = -(g/L)·sin θ`) plus a coupling term to the ship's
    /// lateral acceleration (`-(aₓ/L)·cos θ`), with light angular
    /// damping. Whip the ship too aggressively and `|θ̇|` exceeds the
    /// snap threshold — the tether breaks and the run ends.
    private func pendulumTick() {
        // Capture the ship's lateral force *this frame* before the ship
        // physics step — it's what couples into the pendulum equation.
        let mainBurns = thrustingMain && fuel > 0
        let sideBurns = thrustingLateral != 0 && fuel > 0
        let shipAx: Double = sideBurns ? Double(thrustingLateral) * thrustAccelSide : 0
        _ = mainBurns                              // (silences unused-var if we later add vertical coupling)

        stepShipPhysics()

        // Pendulum equation. Treat θ in radians, time = 1 tick.
        // Angular acceleration from gravity (restoring force toward θ=0):
        let angAccelG = -(gravity / Self.tetherLength) * sin(theta)
        // Coupling from horizontal ship acceleration (causes pendulum lag):
        let angAccelS = -(shipAx / Self.tetherLength) * cos(theta)
        thetaDot += angAccelG + angAccelS
        thetaDot *= (1 - pendulumDamping)
        theta    += thetaDot

        // Tether snap — whip detection. Player must be careful: violent
        // lateral inputs spin the cargo too fast and the rope gives way.
        if abs(thetaDot) > snapAngularRate {
            tetherSnapped = true
            crash(impact: abs(thetaDot))
            return
        }

        // Cargo collision — the CARGO is what needs to touch down softly,
        // not the ship. Compute cargo position via theta.
        let pad = currentTargetPad
        let cX = cargoX
        let cY = cargoY
        let cargoBottom = cY + Self.cargoHalfH
        if cargoBottom >= Double(pad.top) {
            let onPad = cX >= Double(pad.left) + Self.cargoHalfW
                     && cX <= Double(pad.right) - Self.cargoHalfW
                     && cargoBottom <= Double(pad.top) + 2
            if onPad {
                resolvePendulumLanding(pad: pad)
                return
            }
        }
        if cargoBottom >= Double(Self.groundY) {
            crash(impact: abs(cargoVY))
            return
        }

        // Ship-into-ground is still a crash (don't fly the ship down too far).
        if shipY + 6 >= Double(Self.groundY) {
            crash(impact: abs(vy))
        }
    }

    private func resolvePendulumLanding(pad: Pad) {
        let cvy = cargoVY
        let cvx = cargoVX
        let softVertical   = abs(cvy) <= landMaxVY
        let softHorizontal = abs(cvx) <= landMaxVX
        landingImpact = abs(cvy)
        if softVertical && softHorizontal {
            // Pin both ship & cargo: tether becomes a rigid post.
            vx = 0
            vy = 0
            thetaDot = 0
            // Snap the ship up so the cargo sits exactly on the pad.
            shipY = Double(pad.top) - Self.tetherLength * cos(theta) - Self.cargoHalfH
            // Pendulum landing is harder than classic — reward it more.
            score = 1500 + Int(fuel * 10) + max(0, Int((landMaxVY - landingImpact) * 1000))
            phase = .landed
            recordCurrentScore()
        } else {
            crash(impact: abs(cvy))
        }
    }

    // MARK: - Mail Run mode tick

    /// Mail Run mode: deliver to N pads in sequence with a 60-second
    /// clock and a single shared fuel tank. Same ship physics as
    /// Classic — only the win condition (clear all pads) and the
    /// lose conditions (clock expires, fuel runs out and you crash)
    /// differ. Landing on the current target pad advances the index
    /// and continues the mission instead of going to `.landed`.
    private func mailRunTick() {
        stepShipPhysics()

        // Tick the clock first so a frame that runs the clock to 0
        // and ALSO lands on the final pad still resolves as a win
        // (the landing branch returns early; if we time out, it's
        // because no landing happened this frame).
        if timeRemainingTicks > 0 {
            timeRemainingTicks -= 1
        }
        if timeRemainingTicks <= 0 {
            // Out of time — partial-completion score.
            landingImpact = 0
            score = scoreForMailRunPartial()
            phase = .crashed
            recordCurrentScore()
            return
        }

        // Try to land on the current target pad — same shape as Classic.
        let pad = currentTargetPad
        let shipBottom = shipY + 6
        if shipBottom >= Double(pad.top) {
            let halfWidth: Double = 6
            let shipLeft  = shipX - halfWidth
            let shipRight = shipX + halfWidth
            let onPad = shipLeft >= Double(pad.left)
                     && shipRight <= Double(pad.right)
                     && shipBottom <= Double(pad.top) + 2
            if onPad {
                attemptMailRunDelivery(pad: pad)
                return
            }
        }
        if shipBottom >= Double(Self.groundY) {
            // Hit the dirt — partial-completion crash.
            landingImpact = abs(vy)
            score = scoreForMailRunPartial()
            phase = .crashed
            recordCurrentScore()
        }
    }

    /// Called when the ship touches the current target pad's surface.
    /// A soft landing clears the pad and either advances to the next
    /// one (continue playing) or wins the mission. A hard landing is
    /// a crash with partial credit for any pads already cleared.
    private func attemptMailRunDelivery(pad: Pad) {
        let softVertical   = abs(vy) <= landMaxVY
        let softHorizontal = abs(vx) <= landMaxVX
        guard softVertical && softHorizontal else {
            landingImpact = abs(vy)
            score = scoreForMailRunPartial()
            phase = .crashed
            recordCurrentScore()
            return
        }
        // Soft landing — clear this pad.
        if mailRunIndex < mailRunCleared.count {
            mailRunCleared[mailRunIndex] = true
        }
        if mailRunIndex + 1 >= pads.count {
            // All pads cleared — mission complete.
            shipY = Double(pad.top) - 6
            vx = 0
            vy = 0
            landingImpact = abs(vy)
            score = scoreForMailRunWin()
            phase = .landed
            recordCurrentScore()
        } else {
            // Advance to the next pad. Lift the ship just clear of
            // the pad surface so we don't immediately re-collide,
            // then zero vertical velocity (a tap-and-go).
            shipY = Double(pad.top) - 6
            vy = -0.6        // pop the ship off the pad — small assist
            mailRunIndex += 1
        }
    }

    /// Final score for a completed Mail Run mission: base for the win,
    /// plus fuel remaining, plus time bonus, plus a landing-softness
    /// bonus on the final touchdown.
    private func scoreForMailRunWin() -> Int {
        let base       = 2000
        let fuelBonus  = Int(fuel * 10)
        let timeBonus  = (timeRemainingTicks / 6)            // 10pt per second remaining
        let softBonus  = max(0, Int((landMaxVY - landingImpact) * 600))
        return base + fuelBonus + timeBonus + softBonus
    }

    /// Partial-credit score when the mission fails (timeout or crash).
    /// Rewards any pads already delivered so a near-completion run is
    /// worth more than an immediate crash.
    private func scoreForMailRunPartial() -> Int {
        let cleared = mailRunCleared.filter { $0 }.count
        return cleared * 500 + Int(fuel * 4)
    }

    // MARK: - Cave Dive mode tick

    /// Cave Dive mode: descend through a procedurally-generated vertical
    /// cave. Ship physics are the same as Classic; the "ground" is the
    /// cave walls (collision = crash) and the win condition is a soft
    /// landing on the pad sitting in the widened bottom chamber. The
    /// camera follows the ship downward so the cave reveals itself a
    /// screen-height at a time.
    private func caveDiveTick() {
        // Ship physics (gravity, thrust, fuel, integration). We DO NOT
        // call stepShipPhysics() here because that helper has built-in
        // horizontal wraparound + a HUD-based ceiling — neither applies
        // in a vertical cave. So inline a Cave-Dive-shaped variant.

        let mainBurns = thrustingMain && fuel > 0
        let sideBurns = thrustingLateral != 0 && fuel > 0
        if mainBurns { fuel = max(0, fuel - fuelBurnMain) }
        if sideBurns { fuel = max(0, fuel - fuelBurnSide) }

        vy += gravity
        if mainBurns { vy -= thrustAccelMain }
        if sideBurns { vx += Double(thrustingLateral) * thrustAccelSide }

        if fuel <= 0 {
            thrustingMain = false
            thrustingLateral = 0
        }

        shipX += vx
        shipY += vy

        // Cave ceiling — bounce off the top of the world (y=0).
        if shipY < 0 {
            shipY = 0
            vy = abs(vy) * ceilingBounceDamp
        }

        // Camera follows the ship downward. Once the ship is past the
        // upper third of the viewport, the camera scrolls so the ship
        // stays around y=cameraOffsetFromTop in screen space. Clamped
        // so it never reveals past the cave's bottom edge.
        let viewportAnchor: Int = 56   // ship's preferred screen Y
        let desiredCamera = Int(shipY) - viewportAnchor
        let maxCamera = max(0, Self.caveDepth - Self.lcdHeight)
        cameraY = min(maxCamera, max(0, desiredCamera))

        // Wall collision — sample the cave wall at the ship's depth
        // band (we check center and a few rows around so the ship's
        // full height counts, not just one pixel).
        let halfWidth: Double = 6
        let shipLeft  = shipX - halfWidth
        let shipRight = shipX + halfWidth
        let yLo = max(0, Int(shipY) - 5)
        let yHi = min(Self.caveDepth - 1, Int(shipY) + 5)
        for y in yLo...yHi {
            let wallLeft  = Double(caveLeftWall[y])
            let wallRight = Double(caveRightWall[y])
            if shipLeft <= wallLeft || shipRight >= wallRight {
                crash(impact: max(abs(vy), abs(vx)))
                return
            }
        }

        // Pad landing check — same shape as Classic.
        let pad = currentTargetPad
        let shipBottom = shipY + 6
        if shipBottom >= Double(pad.top) {
            let onPad = shipLeft >= Double(pad.left)
                     && shipRight <= Double(pad.right)
                     && shipBottom <= Double(pad.top) + 2
            if onPad {
                resolveCaveDiveLanding(pad: pad)
                return
            }
        }

        // Falling past the cave floor without hitting the pad = crash.
        if Int(shipY) >= Self.caveDepth - 4 {
            crash(impact: abs(vy))
        }
    }

    private func resolveCaveDiveLanding(pad: Pad) {
        let softVertical   = abs(vy) <= landMaxVY
        let softHorizontal = abs(vx) <= landMaxVX
        landingImpact = abs(vy)
        if softVertical && softHorizontal {
            shipY = Double(pad.top) - 6
            vx = 0
            vy = 0
            // Cave Dive scoring rewards depth + softness + fuel.
            // Reaching the pad at all is the hard part, so the base
            // win bonus is the biggest of the three.
            let depthBonus = Int(shipY)             // how deep you got (~480 for win)
            score = 1800 + depthBonus + Int(fuel * 10)
                  + max(0, Int((landMaxVY - landingImpact) * 800))
            phase = .landed
            recordCurrentScore()
        } else {
            crash(impact: abs(vy))
        }
    }

    // MARK: - Shared crash

    private func crash(impact: Double) {
        landingImpact = impact
        vx = 0
        vy = 0
        thetaDot = 0
        phase = .crashed
        recordCurrentScore()
        // Shake harder on harder impacts — amplitude scales linearly
        // with impact up to a cap so a gentle whiff isn't the same as
        // a full smash.
        let amplitude = min(5.0, 2.0 + impact * 2.0)
        cameraShake.trigger(amplitude: amplitude, ticks: 16)
    }

    /// Persist `score` as the new per-mode best if it exceeds the
    /// stored value, and set `isNewBest` for the result banner to
    /// surface. Called from every .landed / .crashed transition.
    private func recordCurrentScore() {
        isNewBest = CartridgeScores.recordIfBetter(
            score, cartridge: Self.cartridgeId, mode: mode.rawValue
        )
    }
}
