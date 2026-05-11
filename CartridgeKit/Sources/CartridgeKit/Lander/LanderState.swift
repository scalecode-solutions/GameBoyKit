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
    /// here as they ship. v1 ships only `.classic`.
    public enum Mode: String, CaseIterable, Sendable, Codable {
        case classic
        // case pendulum, mailRun, caveDive — coming in later iterations.

        public var displayName: String {
            switch self {
            case .classic: return "CLASSIC"
            }
        }

        public var briefing: String {
            switch self {
            case .classic: return "LAND ON THE PAD. SOFT TOUCH."
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

    // Ship physics (Classic — units are logical LCD pixels per tick).
    public private(set) var shipX: Double = 0
    public private(set) var shipY: Double = 0
    public private(set) var vx: Double = 0
    public private(set) var vy: Double = 0
    public private(set) var fuel: Double = 100             // 0…100

    // Last-frame input (for render: flame on, lateral tilt, …)
    public private(set) var thrustingMain: Bool = false
    public private(set) var thrustingLateral: Int = 0      // -1 / 0 / +1

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

    // MARK: - Derived state (for HUD feedback)

    /// True when the ship's current velocity components would qualify
    /// as a soft landing if it touched the pad *right now*. Drives the
    /// in-HUD "SAFE" indicator so the player gets continuous skill
    /// feedback (independent of horizontal alignment with the pad).
    public var landingWouldBeSafe: Bool {
        abs(vy) <= landMaxVY && abs(vx) <= landMaxVX
    }

    /// The vy threshold the HUD treats as "too fast" — public so the
    /// view can flash the readout when the player exceeds it.
    public var landingMaxVY: Double { landMaxVY }

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
    public func applyInput(mainThrust: Bool, lateral: Int) {
        let mainActive = mainThrust && fuel > 0
        let sideActive = lateral != 0 && fuel > 0
        thrustingMain = mainActive
        thrustingLateral = sideActive ? lateral : 0
    }

    // MARK: - Tick

    /// Advance one physics step. The view calls this at ~60Hz while
    /// `.playing`. Idempotent in any other phase.
    public func tick() {
        guard phase == .playing else { return }

        // Latch whether each thruster *actually fires* this frame. We
        // gate on fuel > 0 BEFORE the burn so the very last frame of
        // fuel still gets its boost — feels generous, not stingy.
        let mainBurns = thrustingMain && fuel > 0
        let sideBurns = thrustingLateral != 0 && fuel > 0
        if mainBurns { fuel = max(0, fuel - fuelBurnMain) }
        if sideBurns { fuel = max(0, fuel - fuelBurnSide) }

        // Forces
        vy += gravity
        if mainBurns { vy -= thrustAccelMain }
        if sideBurns { vx += Double(thrustingLateral) * thrustAccelSide }

        // If we just emptied the tank, clear the thrust flags so the
        // next frame has visibly-dry thrusters in render + applyInput
        // gating, and the test assertion holds.
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

        // Ground / pad contact check
        let shipBottom = shipY + 6                 // ship is ~12 tall, half = 6
        if shipBottom >= Double(Self.padTop) {
            // Are we over the pad?
            let halfWidth: Double = 6              // ship is ~12 wide
            let shipLeft  = shipX - halfWidth
            let shipRight = shipX + halfWidth
            let onPad = shipLeft >= Double(Self.padLeft)
                     && shipRight <= Double(Self.padRight)
                     && shipBottom <= Double(Self.padTop) + 2  // not deep into pad

            if onPad {
                resolveLandingOnPad()
                return
            }
        }
        if shipBottom >= Double(Self.groundY) {
            crash()
        }
    }

    // MARK: - Landing resolution

    private func resolveLandingOnPad() {
        let softVertical   = abs(vy) <= landMaxVY
        let softHorizontal = abs(vx) <= landMaxVX
        landingImpact = abs(vy)
        if softVertical && softHorizontal {
            // Snap to the pad surface, freeze, compute score.
            shipY = Double(Self.padTop) - 6
            vx = 0
            vy = 0
            score = 1000 + Int(fuel * 10) + max(0, Int((landMaxVY - landingImpact) * 800))
            phase = .landed
        } else {
            crash()
        }
    }

    private func crash() {
        landingImpact = abs(vy)
        vx = 0
        vy = 0
        phase = .crashed
    }
}
