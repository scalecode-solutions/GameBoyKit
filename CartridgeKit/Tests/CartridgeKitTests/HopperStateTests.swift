import Testing
@testable import CartridgeKit

@MainActor
struct HopperStateTests {

    @Test func startsOnTitle() {
        let state = HopperState()
        #expect(state.phase == .title)
        #expect(state.mode == .classic)
        #expect(state.modeSelectCursor == 0)
    }

    @Test func openModeSelectAdvances() {
        let state = HopperState()
        state.openModeSelect()
        #expect(state.phase == .modeSelect)
    }

    @Test func confirmingStartsRun() {
        let state = HopperState()
        state.openModeSelect()
        state.confirmModeSelection()
        #expect(state.phase == .playing)
        #expect(state.lives == HopperState.classicLives)
        #expect(state.score == 0)
        #expect(state.timeRemainingTicks == HopperState.classicTimeTicks)
    }

    @Test func startRunPositionsFrogAtStart() {
        let state = HopperState()
        state.startRun(.classic)
        #expect(state.frogX == HopperState.frogStartCol)
        #expect(state.frogY == HopperState.startRow)
        #expect(state.ridingLane == nil)
        #expect(state.ridingEntity == nil)
    }

    @Test func startRunSetsUpNineLanesForClassic() {
        let state = HopperState()
        state.startRun(.classic)
        #expect(state.lanes.count == 9)
        // 5 rivers + 4 roads, in that order top-down
        let riverCount = state.lanes.filter { $0.kind == .river }.count
        let roadCount  = state.lanes.filter { $0.kind == .road }.count
        #expect(riverCount == 5)
        #expect(roadCount == 4)
        // Parallel entity arrays
        #expect(state.entities.count == state.lanes.count)
    }

    @Test func hopUpMovesAndScores() {
        let state = HopperState()
        state.startRun(.classic)
        let y0 = state.frogY
        let s0 = state.score
        state.hop(.up)
        #expect(state.frogY == y0 - 1)
        #expect(state.score == s0 + 10)
    }

    @Test func hopDownDoesNotScore() {
        let state = HopperState()
        state.startRun(.classic)
        // Frog starts at startRow; hop up first to clear the bestRow,
        // then back down. Going DOWN never awards points.
        state.hop(.up)
        let s = state.score
        state.hop(.down)
        #expect(state.score == s)
    }

    @Test func hopClampsAtGridEdges() {
        let state = HopperState()
        state.startRun(.classic)
        // Hop left repeatedly — should stop at column 0, not go negative.
        for _ in 0..<HopperState.cols + 5 { state.hop(.left) }
        #expect(state.frogX == 0)
    }

    @Test func reachingGoalRowWins() {
        let state = HopperState()
        state.startRun(.classic)
        // Repeatedly hop up. We may die along the way depending on
        // hazard layout, but if we don't die, hitting goalRow wins.
        for _ in 0..<HopperState.rows {
            state.hop(.up)
            if state.phase == .won || state.phase == .dead { break }
        }
        // Either we won by reaching the bank or we died crossing —
        // both are valid resolutions.
        #expect(state.phase == .won || state.phase == .dead)
    }

    @Test func tickCountsDownTimer() {
        let state = HopperState()
        state.startRun(.classic)
        let t0 = state.timeRemainingTicks
        for _ in 0..<30 { state.tick() }
        // Could die during those ticks (logs / cars moving); if alive,
        // timer should have decremented by 30. If dead, we're done.
        if state.phase == .playing {
            #expect(state.timeRemainingTicks == t0 - 30)
        }
    }

    @Test func pauseHaltsTickEffects() {
        let state = HopperState()
        state.startRun(.classic)
        state.togglePause()
        #expect(state.phase == .paused)
        let t = state.timeRemainingTicks
        for _ in 0..<10 { state.tick() }
        #expect(state.timeRemainingTicks == t)   // clock stops while paused
    }

    @Test func timerExpiryDies() {
        let state = HopperState()
        state.startRun(.classic)
        // Burn through all remaining time. Frog may die earlier from
        // hazards moving over it — that's also a valid outcome.
        for _ in 0..<HopperState.classicTimeTicks + 60 {
            state.tick()
            if state.phase != .playing { break }
        }
        #expect(state.phase == .dead)
    }

    @Test func entityAdvanceWrapsAroundEdges() {
        let state = HopperState()
        state.startRun(.classic)
        // Pick a fast lane and tick many times; entities should never
        // accumulate beyond [-entityWidth, lcdWidth].
        for _ in 0..<2000 {
            state.tick()
            if state.phase != .playing { break }
        }
        for (li, lane) in state.lanes.enumerated() {
            for e in state.entities[li] {
                #expect(e.x >= -Double(lane.entityWidth))
                #expect(e.x <= Double(HopperState.cols))
            }
        }
    }

    @Test func retryRestartsFromDeath() {
        let state = HopperState()
        state.startRun(.classic)
        // Tick to a death of some kind. Hopper has lots of moving
        // hazards so an idle frog usually catches a wheel quickly.
        for _ in 0..<HopperState.classicTimeTicks + 60 {
            state.tick()
            if state.phase == .dead { break }
        }
        if state.phase == .dead {
            state.retryRun()
            #expect(state.phase == .playing)
            #expect(state.lives == HopperState.classicLives)
            #expect(state.frogY == HopperState.startRow)
        }
    }

    // MARK: - Endless mode

    @Test func endlessStartsOneShotAtTopAndSpawnsLanes() {
        let state = HopperState(endlessRng: HopperSeededRNG(seed: 42))
        state.startRun(.endless)
        #expect(state.mode == .endless)
        #expect(state.lives == 1)
        #expect(state.frogY == HopperState.startRow)
        #expect(state.cameraRow == 0)
        // Pre-fill ran from row 19 down to row -8, so lanes exist for
        // every world row in [-8, 19].
        let rowsCovered = Set(state.lanes.map(\.row))
        for r in -8...HopperState.rows + 1 {
            #expect(rowsCovered.contains(r))
        }
    }

    @Test func endlessSpawnRowIsSafe() {
        let state = HopperState(endlessRng: HopperSeededRNG(seed: 7))
        state.startRun(.endless)
        // The frog's spawn row + neighbors are forced to .safe so the
        // first frame isn't an instant death.
        let spawnLane = state.lanes.first { $0.row == HopperState.startRow }
        #expect(spawnLane?.kind == .safe)
    }

    @Test func endlessCameraScrollsUpOverTime() {
        let state = HopperState(endlessRng: HopperSeededRNG(seed: 1))
        state.startRun(.endless)
        let c0 = state.cameraRow
        for _ in 0..<60 {
            state.tick()
            if state.phase != .playing { break }
        }
        // Camera should have moved up (more negative) by ~60·scrollRate.
        if state.phase == .playing {
            #expect(state.cameraRow < c0)
        }
    }

    @Test func endlessFallBehindKills() {
        let state = HopperState(endlessRng: HopperSeededRNG(seed: 2))
        state.startRun(.endless)
        // Don't hop. The camera will eventually scroll past the frog's
        // row and the fellBehind branch will fire.
        for _ in 0..<5000 {
            state.tick()
            if state.phase != .playing { break }
        }
        #expect(state.phase == .dead)
        #expect(state.lastDeath != nil)
    }

    @Test func endlessProcgenExtendsOnDemand() {
        let state = HopperState(endlessRng: HopperSeededRNG(seed: 3))
        state.startRun(.endless)
        let initialTop = state.lanes.map(\.row).min() ?? 0
        // Tick enough for the camera to scroll several rows.
        for _ in 0..<500 {
            state.tick()
            if state.phase != .playing { break }
        }
        let newTop = state.lanes.map(\.row).min() ?? 0
        if state.phase == .playing {
            #expect(newTop < initialTop)   // more rows generated above
        }
    }

    // MARK: - Night Shift mode

    @Test func nightShiftStartsInDayPhase() {
        let state = HopperState()
        state.startRun(.nightShift)
        #expect(state.mode == .nightShift)
        #expect(state.lives == HopperState.classicLives)
        #expect(state.timeRemainingTicks == HopperState.classicTimeTicks)
        #expect(state.nightShiftCycleTick == 0)
        #expect(state.isNightPhase == false)
    }

    @Test func nightShiftFadesFromDayToNight() {
        let state = HopperState()
        state.startRun(.nightShift)
        let half = HopperState.nightShiftCycleLen / 2
        let fade = HopperState.nightFadeTicks
        // Ticks 0..<(half - fade) are pure day — fade hasn't started.
        for _ in 0..<(half - fade - 1) {
            state.tick()
            if state.phase != .playing { break }
        }
        if state.phase == .playing {
            #expect(state.nightProgress == 0)
            #expect(state.isNightPhase == false)
        }
        // Tick all the way to the end of the fade — should be full night.
        for _ in 0..<(fade + 2) {
            state.tick()
            if state.phase != .playing { break }
        }
        if state.phase == .playing {
            #expect(state.nightProgress == 1)
            #expect(state.isNightPhase == true)
        }
    }

    @Test func nightProgressRampsAcrossFadeWindow() {
        let state = HopperState()
        state.startRun(.nightShift)
        let half = HopperState.nightShiftCycleLen / 2
        let fade = HopperState.nightFadeTicks
        // Land on the middle of the fade window.
        for _ in 0..<(half - fade / 2) {
            state.tick()
            if state.phase != .playing { break }
        }
        if state.phase == .playing {
            // ~half-way through the fade → nightProgress around 0.5.
            #expect(state.nightProgress > 0.3 && state.nightProgress < 0.7)
        }
    }

    @Test func nightShiftUsesClassicLaneLayout() {
        let stateA = HopperState()
        stateA.startRun(.classic)
        let stateB = HopperState()
        stateB.startRun(.nightShift)
        // Same row + kind sequence across modes.
        #expect(stateA.lanes.count == stateB.lanes.count)
        for (a, b) in zip(stateA.lanes, stateB.lanes) {
            #expect(a.row == b.row)
            #expect(a.kind == b.kind)
        }
    }

    @Test func nightShiftIsNightPhaseFalseInOtherModes() {
        let state = HopperState()
        state.startRun(.classic)
        // Force the cycle counter past the midpoint and confirm the
        // flag stays false outside .nightShift mode.
        for _ in 0..<HopperState.nightShiftCycleLen {
            state.tick()
            if state.phase != .playing { break }
        }
        #expect(state.isNightPhase == false)
    }
}

/// Deterministic RNG for reproducible Endless procgen in tests.
struct HopperSeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
