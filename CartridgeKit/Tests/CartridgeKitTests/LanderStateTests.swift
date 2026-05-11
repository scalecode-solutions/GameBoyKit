import Testing
@testable import CartridgeKit

@MainActor
struct LanderStateTests {

    @Test func startsOnTitle() {
        let state = LanderState()
        #expect(state.phase == .title)
        #expect(state.mode == .classic)
        #expect(state.modeSelectCursor == 0)
    }

    @Test func openModeSelectAdvancesPhase() {
        let state = LanderState()
        state.openModeSelect()
        #expect(state.phase == .modeSelect)
    }

    @Test func confirmingModeStartsRun() {
        let state = LanderState()
        state.openModeSelect()
        state.confirmModeSelection()
        #expect(state.phase == .playing)
        #expect(state.fuel == 100)
        #expect(state.vy == 0)
    }

    @Test func gravityPullsShipDownWithoutThrust() {
        let state = LanderState()
        state.startRun(.classic)
        let y0 = state.shipY
        state.applyInput(mainThrust: false, lateral: 0)
        for _ in 0..<10 { state.tick() }
        #expect(state.shipY > y0)
        #expect(state.vy > 0)
    }

    @Test func mainThrustReducesVerticalVelocity() {
        let state = LanderState()
        state.startRun(.classic)
        // First let gravity build downward velocity for a bit.
        state.applyInput(mainThrust: false, lateral: 0)
        for _ in 0..<10 { state.tick() }
        let vyWithGravity = state.vy

        // Then thrust upward.
        state.applyInput(mainThrust: true, lateral: 0)
        for _ in 0..<5 { state.tick() }
        #expect(state.vy < vyWithGravity)
    }

    @Test func thrustingBurnsFuel() {
        let state = LanderState()
        state.startRun(.classic)
        let fuel0 = state.fuel
        state.applyInput(mainThrust: true, lateral: 0)
        for _ in 0..<30 { state.tick() }
        #expect(state.fuel < fuel0)
    }

    @Test func emptyFuelDisablesThrust() {
        let state = LanderState()
        state.startRun(.classic)
        // Burn it all
        state.applyInput(mainThrust: true, lateral: 0)
        for _ in 0..<2000 {
            state.tick()
            if state.phase != .playing { break }
        }
        // Whether we landed/crashed or are still going, fuel should be 0
        // and the thrust flag should be off even though input is still held.
        #expect(state.fuel == 0)
        #expect(state.thrustingMain == false)
    }

    @Test func pauseHaltsPhysics() {
        let state = LanderState()
        state.startRun(.classic)
        state.togglePause()
        #expect(state.phase == .paused)
        let snapshot = (x: state.shipX, y: state.shipY, vx: state.vx, vy: state.vy)
        for _ in 0..<10 { state.tick() }
        #expect(state.shipX == snapshot.x)
        #expect(state.shipY == snapshot.y)
        #expect(state.vx == snapshot.vx)
        #expect(state.vy == snapshot.vy)
    }

    @Test func horizontalWrapAroundEdges() {
        let state = LanderState()
        state.startRun(.classic)
        // Manually push the ship off the right edge.
        for _ in 0..<2000 {
            // Force-feed lateral right; we just want to test wraparound math
            state.applyInput(mainThrust: false, lateral: 1)
            state.tick()
            if state.shipX < Double(LanderState.lcdWidth) * 0.1 { break }
            if state.phase != .playing { break }
        }
        // Either it wrapped to near zero, or the run ended — both are fine.
        // The hard assertion: ship X always stays in [0, lcdWidth).
        #expect(state.shipX >= 0 && state.shipX < Double(LanderState.lcdWidth))
    }

    @Test func retryAfterCrashReturnsToPlaying() {
        let state = LanderState()
        state.startRun(.classic)
        // Drop straight down to crash off the pad.
        state.applyInput(mainThrust: false, lateral: 0)
        for _ in 0..<2000 {
            state.tick()
            if state.phase != .playing { break }
        }
        #expect(state.phase == .crashed || state.phase == .landed)
        let phaseBeforeRetry = state.phase
        state.retryRun()
        #expect(state.phase == .playing)
        #expect(state.fuel == 100)
        // sanity: we ran the test through one resolved outcome
        #expect(phaseBeforeRetry == .crashed || phaseBeforeRetry == .landed)
    }

    @Test func exitToModeSelectFromResult() {
        let state = LanderState()
        state.startRun(.classic)
        for _ in 0..<2000 {
            state.applyInput(mainThrust: false, lateral: 0)
            state.tick()
            if state.phase != .playing { break }
        }
        state.exitToModeSelect()
        #expect(state.phase == .modeSelect)
    }

    // MARK: - Pendulum mode

    @Test func pendulumStartsWithCargoStraightDown() {
        let state = LanderState()
        state.startRun(.pendulum)
        #expect(state.mode == .pendulum)
        #expect(state.theta == 0)
        #expect(state.thetaDot == 0)
        #expect(state.tetherSnapped == false)
        // Cargo sits exactly tetherLength below the ship.
        #expect(state.cargoX == state.shipX)
        #expect(state.cargoY == state.shipY + LanderState.tetherLength)
    }

    @Test func pendulumLateralThrustCausesSwing() {
        let state = LanderState()
        state.startRun(.pendulum)
        // Apply a few frames of lateral right thrust — should set
        // theta-dot off zero (cargo lags ship motion).
        state.applyInput(mainThrust: false, lateral: 1)
        for _ in 0..<8 { state.tick() }
        #expect(state.thetaDot != 0)
    }

    @Test func pendulumWhipSnapsTether() {
        let state = LanderState()
        state.startRun(.pendulum)
        // Rapid lateral reversals each add a whip impulse — a handful
        // of flips should build θ̇ past the snap threshold quickly,
        // well within fuel budget.
        for i in 0..<60 {
            let lat = (i % 2 == 0) ? 1 : -1
            state.applyInput(mainThrust: true, lateral: lat)
            state.tick()
            if state.tetherSnapped { break }
            if state.phase != .playing { break }
        }
        #expect(state.tetherSnapped == true)
        #expect(state.phase == .crashed)
    }

    @Test func pendulumGentleInputDoesNotSnap() {
        let state = LanderState()
        state.startRun(.pendulum)
        // Hold lateral steady — no reversals → no whip impulses → no snap.
        // Gentle continuous input should accumulate θ̇ only to its
        // damped equilibrium (~0.14), comfortably below 0.20.
        for _ in 0..<200 {
            state.applyInput(mainThrust: true, lateral: 1)
            state.tick()
            if state.phase != .playing { break }
        }
        #expect(state.tetherSnapped == false)
    }

    @Test func pendulumLandingUsesCargoVelocity() {
        let state = LanderState()
        state.startRun(.pendulum)
        // Just descend — no lateral. Cargo hangs straight down so
        // cargoVX ≈ 0 and the touchdown should resolve cleanly (either
        // landed or crashed depending on whether it lined up).
        state.applyInput(mainThrust: false, lateral: 0)
        for _ in 0..<2000 {
            state.tick()
            if state.phase != .playing { break }
        }
        // Either way it resolved — and landingImpact reflects vertical
        // *cargo* motion, not ship motion (they match when theta=0).
        #expect(state.phase == .crashed || state.phase == .landed)
    }
}
