import Testing
import CoreGraphics
@testable import GameBoyKit

@MainActor
struct GameBoyInputTests {

    @Test func dpadStartsNil() {
        let input = GameBoyInput()
        #expect(input.dpad == nil)
        #expect(input.isPressed(.dpadUp) == false)
        #expect(input.isPressed(.dpadDown) == false)
    }

    @Test func settingDPadExposesAxisFlags() {
        let input = GameBoyInput()
        input.setDPad(.up)
        #expect(input.dpad == .up)
        #expect(input.isPressed(.dpadUp))
        #expect(!input.isPressed(.dpadDown))

        input.setDPad(.upRight)
        #expect(input.isPressed(.dpadUp))
        #expect(input.isPressed(.dpadRight))
        #expect(!input.isPressed(.dpadLeft))
    }

    @Test func faceButtonsTrackPressedState() {
        let input = GameBoyInput()
        input.setButton(.a, pressed: true)
        #expect(input.aPressed)
        #expect(input.isPressed(.a))
        input.setButton(.a, pressed: false)
        #expect(!input.aPressed)
    }

    @Test func eventsStreamReceivesPressAndRelease() async {
        let input = GameBoyInput()
        var receivedEvents: [ButtonEvent] = []
        let task = Task { @MainActor in
            for await event in input.events {
                receivedEvents.append(event)
                if receivedEvents.count == 2 { break }
            }
        }
        // Give the AsyncStream a beat to subscribe.
        try? await Task.sleep(for: .milliseconds(20))
        input.setButton(.b, pressed: true)
        input.setButton(.b, pressed: false)
        _ = await task.value

        #expect(receivedEvents.count == 2)
        #expect(receivedEvents[0].button == .b)
        #expect(receivedEvents[0].phase == .pressed)
        #expect(receivedEvents[1].phase == .released)
    }

    @Test func dPadDirectionFromOffsetReturnsNilInDeadZone() {
        #expect(DPadDirection.from(offset: .init(x: 0, y: 0)) == nil)
        #expect(DPadDirection.from(offset: .init(x: 0.05, y: 0.05)) == nil)
    }

    @Test func dPadDirectionBuckets8Slices() {
        // y is screen-down (positive y = down).
        #expect(DPadDirection.from(offset: .init(x: 0,    y: -1)) == .up)
        #expect(DPadDirection.from(offset: .init(x: 1,    y:  0)) == .right)
        #expect(DPadDirection.from(offset: .init(x: 0,    y:  1)) == .down)
        #expect(DPadDirection.from(offset: .init(x: -1,   y:  0)) == .left)
        #expect(DPadDirection.from(offset: .init(x: 0.7,  y: -0.7)) == .upRight)
        #expect(DPadDirection.from(offset: .init(x: -0.7, y:  0.7)) == .downLeft)
    }
}
