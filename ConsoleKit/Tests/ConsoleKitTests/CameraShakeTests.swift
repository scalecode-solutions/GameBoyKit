import Testing
@testable import ConsoleKit

struct CameraShakeTests {

    @Test func startsInactiveWithZeroOffset() {
        let shake = CameraShake()
        #expect(shake.isActive == false)
        #expect(shake.offsetX == 0)
        #expect(shake.offsetY == 0)
    }

    @Test func triggerActivates() {
        var shake = CameraShake()
        shake.trigger()
        #expect(shake.isActive == true)
    }

    @Test func tickReducesAmplitudeToZero() {
        var shake = CameraShake()
        shake.trigger(amplitude: 4, ticks: 10)
        for _ in 0..<20 { shake.tick() }
        #expect(shake.isActive == false)
        #expect(shake.offsetX == 0)
        #expect(shake.offsetY == 0)
    }

    @Test func offsetStaysWithinAmplitudeRadius() {
        var shake = CameraShake(decay: 1.0)  // no decay so amplitude stays put
        shake.trigger(amplitude: 5, ticks: 30)
        for _ in 0..<30 {
            shake.tick()
            #expect(abs(shake.offsetX) <= 5)
            #expect(abs(shake.offsetY) <= 5)
        }
    }

    @Test func subsequentTriggersExtendOrStrengthenButDoNotShorten() {
        var shake = CameraShake()
        shake.trigger(amplitude: 4, ticks: 10)
        // Weaker, shorter trigger shouldn't shorten the existing shake.
        shake.trigger(amplitude: 1, ticks: 2)
        #expect(shake.isActive == true)
        // Run out the original 10-tick budget — should still be active
        // for most of it.
        for _ in 0..<8 { shake.tick() }
        #expect(shake.isActive == true)
    }
}
