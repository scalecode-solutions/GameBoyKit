import Foundation

/// Tiny particle system for one-shot effect bursts (touchdown dust,
/// goal-reached confetti, etc.). A cartridge's state holds one of
/// these, calls `burst` on a celebratory event, and `tick`s it each
/// frame; the view iterates `particles` and draws each as a 1-2
/// pixel speck with optional alpha-fade based on remaining life.
///
/// Value type so it nests cleanly inside `@Observable` state classes
/// without owning a separate observation lifecycle.
public struct ParticleSystem: Sendable {

    public struct Particle: Sendable {
        public var x: Double
        public var y: Double
        public var vx: Double
        public var vy: Double
        /// Ticks of life remaining. Particle is culled when this hits zero.
        public var life: Int
        /// Initial life so the view can compute a 0..1 fade factor.
        public let initialLife: Int
    }

    public private(set) var particles: [Particle] = []

    /// Per-tick downward acceleration applied to each particle's vy.
    /// Lighter than gameplay gravity so the burst arcs feel airy.
    public var gravity: Double = 0.05

    /// Per-tick horizontal drag (vx multiplier) so the spread settles
    /// instead of flying off to the edges.
    public var drag: Double = 0.96

    public init() {}

    /// Spawn a fresh burst of `count` particles at `point`. Each
    /// particle gets a random angle + speed; vy is biased upward so
    /// the initial fan reads as "lifted" not "splattered".
    public mutating func burst(
        at point: (x: Double, y: Double),
        count: Int = 12,
        speedRange: ClosedRange<Double> = 0.6...2.0,
        lifeRange: ClosedRange<Int> = 18...32,
        upwardBias: Double = 0.5
    ) {
        for _ in 0..<count {
            let angle = Double.random(in: 0..<(.pi * 2))
            let speed = Double.random(in: speedRange)
            let life  = Int.random(in: lifeRange)
            particles.append(Particle(
                x: point.x, y: point.y,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed - upwardBias,
                life: life,
                initialLife: life
            ))
        }
    }

    /// Advance every particle one frame: integrate velocity + gravity,
    /// apply drag, decrement life, cull expired particles.
    public mutating func tick() {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vy += gravity
            particles[i].vx *= drag
            particles[i].life -= 1
        }
        particles.removeAll { $0.life <= 0 }
    }

    /// Removes all particles immediately (useful when restarting a
    /// run — the previous burst shouldn't bleed into the new game).
    public mutating func clear() {
        particles.removeAll()
    }

    public var isActive: Bool { !particles.isEmpty }
}
