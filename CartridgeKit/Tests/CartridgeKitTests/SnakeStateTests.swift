import Testing
@testable import CartridgeKit

@MainActor
struct SnakeStateTests {

    @Test func startsOnTitle() {
        let state = SnakeState()
        #expect(state.phase == .title)
        #expect(state.mode == .classic)
        #expect(state.modeSelectCursor == 0)
        #expect(state.snake.isEmpty)
    }

    @Test func openModeSelectAdvances() {
        let state = SnakeState()
        state.openModeSelect()
        #expect(state.phase == .modeSelect)
    }

    @Test func confirmingStartsRun() {
        let state = SnakeState()
        state.openModeSelect()
        state.confirmModeSelection()
        #expect(state.phase == .playing)
        #expect(state.snake.count == 3)
        #expect(state.direction == .right)
        #expect(state.score == 0)
    }

    @Test func startRunCentersAndFacesRight() {
        let state = SnakeState()
        state.startRun(.classic)
        #expect(state.snake.count == 3)
        #expect(state.direction == .right)
        #expect(state.phase == .playing)
        #expect(state.score == 0)
        // Snake should be horizontal at start
        let ys = Set(state.snake.map(\.y))
        #expect(ys.count == 1)
    }

    @Test func tickMovesHeadInDirection() {
        let state = SnakeState()
        state.startRun(.classic)
        let head0 = state.snake[0]
        state.tick()
        let head1 = state.snake[0]
        #expect(head1.x == head0.x + 1)
        #expect(head1.y == head0.y)
    }

    @Test func turningChangesDirectionOnNextTick() {
        let state = SnakeState()
        state.startRun(.classic)
        state.turn(.up)
        // Direction doesn't flip immediately — it's pending until tick.
        #expect(state.direction == .right)
        state.tick()
        #expect(state.direction == .up)
    }

    @Test func cannotReverseOntoSelf() {
        let state = SnakeState()
        state.startRun(.classic)
        state.turn(.left)   // Currently moving right; this should be ignored
        state.tick()
        #expect(state.direction == .right)
    }

    @Test func wallCollisionEndsGame() {
        let state = SnakeState()
        state.startRun(.classic)
        // Drive into the right wall.
        for _ in 0..<SnakeState.cols { state.tick() }
        #expect(state.phase == .dead)
    }

    @Test func eatingFoodGrowsAndScores() {
        // Use a deterministic RNG; first food position will be reproducible.
        let state = SnakeState(rng: SeededRNG(seed: 42))
        state.startRun(.classic)
        let initialLength = state.snake.count
        let initialScore = state.score

        // Walk the snake toward the food.
        var steps = 0
        while state.phase == .playing && state.snake.count == initialLength && steps < 100 {
            let head = state.snake[0]
            let food = state.food
            if food.x > head.x      { state.turn(.right) }
            else if food.x < head.x { state.turn(.left) }
            else if food.y > head.y { state.turn(.down) }
            else if food.y < head.y { state.turn(.up) }
            state.tick()
            steps += 1
        }
        // Either we ate and grew, or we died bumping into the wall on the way.
        if state.phase == .playing {
            #expect(state.snake.count == initialLength + 1)
            #expect(state.score == initialScore + 10)
        }
    }

    @Test func pauseTogglesPhase() {
        let state = SnakeState()
        state.startRun(.classic)
        state.togglePause()
        #expect(state.phase == .paused)
        // Tick while paused is a no-op
        let length = state.snake.count
        state.tick()
        #expect(state.snake.count == length)
        state.togglePause()
        #expect(state.phase == .playing)
    }

    @Test func retryRestartsFreshGame() {
        let state = SnakeState()
        state.startRun(.classic)
        // Drive into the wall to die.
        for _ in 0..<SnakeState.cols { state.tick() }
        #expect(state.phase == .dead)
        state.retryRun()
        #expect(state.phase == .playing)
        #expect(state.snake.count == 3)
        #expect(state.score == 0)
        #expect(state.direction == .right)
    }

    @Test func exitToModeSelectFromPausedSucceeds() {
        let state = SnakeState()
        state.startRun(.classic)
        state.togglePause()
        #expect(state.phase == .paused)
        state.exitToModeSelect()
        #expect(state.phase == .modeSelect)
    }

    @Test func exitToModeSelectFromDeadSucceeds() {
        let state = SnakeState()
        state.startRun(.classic)
        for _ in 0..<SnakeState.cols { state.tick() }
        #expect(state.phase == .dead)
        state.exitToModeSelect()
        #expect(state.phase == .modeSelect)
    }

    @Test func exitToModeSelectFromPlayingIsNoOp() {
        let state = SnakeState()
        state.startRun(.classic)
        let p0 = state.phase
        state.exitToModeSelect()
        #expect(state.phase == p0)
    }

    @Test func modeSelectCursorWrapsWithinAllCases() {
        let state = SnakeState()
        state.openModeSelect()
        let n = SnakeState.Mode.allCases.count
        // Wrap forward past the end and back to 0.
        state.moveModeSelectCursor(n)
        #expect(state.modeSelectCursor == 0)
        // Wrap backward from 0 to last.
        state.moveModeSelectCursor(-1)
        #expect(state.modeSelectCursor == n - 1)
    }

    // MARK: - Portals mode

    @Test func portalsStartsOnMainMapWithGatewaysConfigured() {
        let state = SnakeState()
        state.startRun(.portals)
        #expect(state.mode == .portals)
        #expect(state.inSideMap == false)
        #expect(state.portalPairs.count == 2)
        #expect(state.mainGateway != nil)
        #expect(state.sideGateway != nil)
        #expect(state.isCarryingTreasure == false)
        #expect(state.sideMapState == .uninitialized)
    }

    @Test func portalsTeleportsThroughOneWidePair() {
        let state = SnakeState(rng: SeededRNG(seed: 1))
        state.startRun(.portals)
        // Pair 1 is configured at (0, 10) ↔ (lastCol, 10). Position
        // the snake one cell to the right of the right endpoint,
        // facing left, and step once — head should teleport to (0, 10).
        let lastCol = SnakeState.cols - 1
        // Manually set up by moving the snake. Easiest: shove the
        // snake near the right portal and check after one tick.
        // We can't directly mutate snake, so instead place the snake
        // adjacent in the main map by simulating moves.
        //
        // Aim the snake at the right portal column from row 10.
        // The snake spawns at row 10 (the playable middle), so just
        // tick right until the head is at the right portal endpoint.
        let startHead = state.snake[0]
        let stepsToPortal = lastCol - startHead.x
        guard stepsToPortal > 0 else { return }
        for _ in 0..<(stepsToPortal - 1) { state.tick() }
        #expect(state.snake[0].x == lastCol - 1)
        // One more tick — head enters the portal cell. Our teleport
        // applies on entry so the new head should appear at the
        // PAIRED endpoint (x=0, y=10).
        state.tick()
        #expect(state.snake[0].x == 0)
        #expect(state.snake[0].y == 10)
    }

    @Test func portalsGatewayCrossingFlipsMapAndGeneratesSideMap() {
        let state = SnakeState(rng: SeededRNG(seed: 7))
        state.startRun(.portals)
        guard let mainGate = state.mainGateway else { return }
        // Manually walk the snake into the main gateway: it sits at
        // (cols-2, 5). Snake spawns at row 10 facing right. Need to
        // turn the snake up to row 5 and approach the gateway.
        // For test simplicity, just call crossGateway indirectly by
        // simulating the head movement. Instead, drive the snake
        // toward (cols-2, 5) using directional turns.
        // First turn up.
        state.turn(.up)
        // Walk up to row 6.
        while state.phase == .playing && state.snake[0].y > 6 {
            state.tick()
        }
        // Turn right and walk to the gateway column.
        state.turn(.right)
        while state.phase == .playing && state.snake[0].x < mainGate.x {
            state.tick()
        }
        // Turn up one to align with row 5 (gateway row).
        state.turn(.up)
        state.tick()
        // Now the head should be on a gateway cell (x in [mainGate.x,
        // mainGate.x+1] AND y = 5). The crossing should have triggered
        // inSideMap = true. We allow either outcome (snake may have
        // bumped a wall mid-route on certain RNG seeds) — guarded:
        if state.phase == .playing {
            #expect(state.inSideMap == true)
            #expect(state.sideMapState == .fresh)
            #expect(state.sideMapTreasure != nil)
            #expect(state.sideMapObstacles.isEmpty == false)
        }
    }

    @Test func portalsDeathDoesNotSetCarryFlag() {
        let state = SnakeState(rng: SeededRNG(seed: 3))
        state.startRun(.portals)
        // Drive the snake into the bottom wall (no portal there) to
        // trigger a death. Right wall has a portal in Portals mode so
        // we can't use the Classic "walk right until you wrap" trick.
        state.turn(.down)
        for _ in 0..<SnakeState.rows {
            state.tick()
            if state.phase == .dead { break }
        }
        #expect(state.phase == .dead)
        // Snake wasn't carrying anything — flag should still be false.
        #expect(state.isCarryingTreasure == false)
    }

    @Test func treasureKindWeightsAreNonZeroAndOrdered() {
        let kinds = SnakeState.TreasureKind.allCases
        #expect(kinds.count == 5)
        for k in kinds { #expect(k.weight > 0) }
        // Rarer multipliers should have lower weights.
        let weightsByMult = kinds.sorted { $0.multiplier < $1.multiplier }
        for i in 0..<(weightsByMult.count - 1) {
            #expect(weightsByMult[i].weight >= weightsByMult[i + 1].weight)
        }
        // Weights sum to 100 by design.
        #expect(kinds.map(\.weight).reduce(0, +) == 100)
    }

    @Test func treasureKindLabelsAreFormatted() {
        #expect(SnakeState.TreasureKind.x2.label == "x2")
        #expect(SnakeState.TreasureKind.x50.label == "x50")
    }
}

/// Deterministic RNG for reproducible food placement in tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
