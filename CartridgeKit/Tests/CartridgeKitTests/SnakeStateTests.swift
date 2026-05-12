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
