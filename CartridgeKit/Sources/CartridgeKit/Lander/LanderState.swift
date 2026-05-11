import Foundation
import Observation

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

    /// Single landing pad geometry for Classic mode (fixed location v1).
    public static let padLeft:  Int = 168
    public static let padRight: Int = 196      // exclusive
    public static let padTop:   Int = 116      // top of pad surface
    public static var padWidth: Int { padRight - padLeft }

    // MARK: - Types

    /// Which mode the player is currently inside. New modes append cases
    /// here as they ship.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        case pendulum
        // case mailRun, caveDive — coming in later iterations.

        public var displayName: String {
            switch self {
            case .classic:  return "CLASSIC"
            case .pendulum: return "PENDULUM"
            }
        }

        public var briefing: String {
            switch self {
            case .classic:  return "LAND ON THE PAD. SOFT TOUCH."
            case .pendulum: return "CARGO ON A TETHER. NO WHIPPING."
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

    // Result data
    public private(set) var score: Int = 0
    public private(set) var landingImpact: Double = 0      // |vy| at touchdown

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
        case .classic:
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
        shipX = Double(Self.lcdWidth) * 0.18           // start near top-left
        shipY = Double(Self.hudHeight) + 6
        vx = 0                                          // no starting drift — let the player orient first
        vy = 0
        fuel = 100
        score = 0
        landingImpact = 0
        thrustingMain = false
        thrustingLateral = 0
        // Pendulum: cargo hangs at rest directly below the ship.
        theta = 0
        thetaDot = 0
        tetherSnapped = false
        phase = .playing
    }

    /// After a result screen, retry the same mode.
    public func retryRun() {
        guard phase == .landed || phase == .crashed else { return }
        startRun(mode)
    }

    /// After a result screen, back out to the mode-select grid.
    public func exitToModeSelect() {
        guard phase == .landed || phase == .crashed else { return }
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

    /// Advance one physics step. The view calls this at ~60Hz while
    /// `.playing`. Idempotent in any other phase. Dispatches by mode.
    public func tick() {
        guard phase == .playing else { return }
        switch mode {
        case .classic:  classicTick()
        case .pendulum: pendulumTick()
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

        // Ground / pad contact check — uses ship body
        let shipBottom = shipY + 6                 // ship is ~12 tall, half = 6
        if shipBottom >= Double(Self.padTop) {
            let halfWidth: Double = 6              // ship is ~12 wide
            let shipLeft  = shipX - halfWidth
            let shipRight = shipX + halfWidth
            let onPad = shipLeft >= Double(Self.padLeft)
                     && shipRight <= Double(Self.padRight)
                     && shipBottom <= Double(Self.padTop) + 2

            if onPad {
                resolveClassicLanding()
                return
            }
        }
        if shipBottom >= Double(Self.groundY) {
            crash(impact: abs(vy))
        }
    }

    private func resolveClassicLanding() {
        let softVertical   = abs(vy) <= landMaxVY
        let softHorizontal = abs(vx) <= landMaxVX
        landingImpact = abs(vy)
        if softVertical && softHorizontal {
            shipY = Double(Self.padTop) - 6
            vx = 0
            vy = 0
            score = 1000 + Int(fuel * 10) + max(0, Int((landMaxVY - landingImpact) * 800))
            phase = .landed
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
        let cX = cargoX
        let cY = cargoY
        let cargoBottom = cY + Self.cargoHalfH
        if cargoBottom >= Double(Self.padTop) {
            let onPad = cX >= Double(Self.padLeft) + Self.cargoHalfW
                     && cX <= Double(Self.padRight) - Self.cargoHalfW
                     && cargoBottom <= Double(Self.padTop) + 2
            if onPad {
                resolvePendulumLanding()
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

    private func resolvePendulumLanding() {
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
            shipY = Double(Self.padTop) - Self.tetherLength * cos(theta) - Self.cargoHalfH
            // Pendulum landing is harder than classic — reward it more.
            score = 1500 + Int(fuel * 10) + max(0, Int((landMaxVY - landingImpact) * 1000))
            phase = .landed
        } else {
            crash(impact: abs(cvy))
        }
    }

    // MARK: - Shared crash

    private func crash(impact: Double) {
        landingImpact = impact
        vx = 0
        vy = 0
        thetaDot = 0
        phase = .crashed
    }
}
