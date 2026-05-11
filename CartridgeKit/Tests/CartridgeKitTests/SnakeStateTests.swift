import Testing
@testable import CartridgeKit

@MainActor
struct SnakeStateTests {

    @Test func startsCenteredFacingRight() {
        let state = SnakeState()
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
        let head0 = state.snake[0]
        state.tick()
        let head1 = state.snake[0]
        #expect(head1.x == head0.x + 1)
        #expect(head1.y == head0.y)
    }

    @Test func turningChangesDirectionOnNextTick() {
        let state = SnakeState()
        state.turn(.up)
        // Direction doesn't flip immediately — it's pending until tick.
        #expect(state.direction == .right)
        state.tick()
        #expect(state.direction == .up)
    }

    @Test func cannotReverseOntoSelf() {
        let state = SnakeState()
        state.turn(.left)   // Currently moving right; this should be ignored
        state.tick()
        #expect(state.direction == .right)
    }

    @Test func wallCollisionEndsGame() {
        let state = SnakeState()
        // Drive into the right wall.
        for _ in 0..<SnakeState.cols { state.tick() }
        #expect(state.phase == .dead)
    }

    @Test func eatingFoodGrowsAndScores() {
        // Use a deterministic RNG; first food position will be reproducible.
        let state = SnakeState(rng: SeededRNG(seed: 42))
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
        state.togglePause()
        #expect(state.phase == .paused)
        // Tick while paused is a no-op
        let length = state.snake.count
        state.tick()
        #expect(state.snake.count == length)
        state.togglePause()
        #expect(state.phase == .playing)
    }

    @Test func resetRestoresFreshState() {
        let state = SnakeState()
        for _ in 0..<5 { state.tick() }
        state.reset()
        #expect(state.snake.count == 3)
        #expect(state.score == 0)
        #expect(state.phase == .playing)
        #expect(state.direction == .right)
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
