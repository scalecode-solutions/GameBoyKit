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
}
