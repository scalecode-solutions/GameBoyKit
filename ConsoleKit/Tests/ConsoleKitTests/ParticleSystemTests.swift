import Testing
@testable import ConsoleKit

struct ParticleSystemTests {

    @Test func startsEmpty() {
        let ps = ParticleSystem()
        #expect(ps.particles.isEmpty)
        #expect(ps.isActive == false)
    }

    @Test func burstSpawnsRequestedCount() {
        var ps = ParticleSystem()
        ps.burst(at: (10, 10), count: 8)
        #expect(ps.particles.count == 8)
        #expect(ps.isActive == true)
    }

    @Test func tickAdvancesPositions() {
        var ps = ParticleSystem()
        ps.burst(at: (50, 50), count: 4)
        let snapshot = ps.particles.map { ($0.x, $0.y) }
        ps.tick()
        let after = ps.particles.map { ($0.x, $0.y) }
        // At least one coordinate should have moved for at least one
        // particle (random velocities, so we can't be precise).
        let anyMoved = zip(snapshot, after).contains { before, after in
            before.0 != after.0 || before.1 != after.1
        }
        #expect(anyMoved)
    }

    @Test func tickEventuallyCullsAllParticles() {
        var ps = ParticleSystem()
        ps.burst(at: (0, 0), count: 6, lifeRange: 4...4)
        // After ticks beyond the lifeRange the system should be empty.
        for _ in 0..<10 { ps.tick() }
        #expect(ps.particles.isEmpty)
        #expect(ps.isActive == false)
    }

    @Test func clearRemovesAllParticles() {
        var ps = ParticleSystem()
        ps.burst(at: (0, 0), count: 10)
        ps.clear()
        #expect(ps.particles.isEmpty)
    }

    @Test func initialLifeMatchesLifeOnSpawn() {
        var ps = ParticleSystem()
        ps.burst(at: (0, 0), count: 5)
        for p in ps.particles {
            #expect(p.life == p.initialLife)
        }
    }

    @Test func gravityAccumulatesOnVY() {
        var ps = ParticleSystem()
        ps.burst(at: (0, 0), count: 1, speedRange: 0...0, upwardBias: 0)
        // One particle with all-zero velocity components; gravity
        // should push vy positive over a few ticks.
        ps.tick()
        ps.tick()
        ps.tick()
        if let p = ps.particles.first {
            #expect(p.vy > 0)
        }
    }
}
