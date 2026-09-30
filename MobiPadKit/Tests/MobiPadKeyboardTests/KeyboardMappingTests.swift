#if os(macOS)
import Carbon.HIToolbox
import CoreGraphics
import MobiPadProtocol
import Testing
@testable import MobiPadKeyboard

/// Only the mapping is tested: posting key events from a test would type into whatever has focus.
struct KeyboardMappingTests {
    let mapping = KeyboardMapping.default

    @Test func neutralStateHoldsNoKeys() {
        #expect(mapping.keys(for: ControllerState()).isEmpty)
    }

    @Test func mapsButtonsByPosition() {
        let keys = mapping.keys(for: ControllerState(buttons: [.a, .dpadUp, .menu]))
        #expect(keys == [CGKeyCode(kVK_ANSI_X), CGKeyCode(kVK_UpArrow), CGKeyCode(kVK_ANSI_Equal)])
    }

    @Test func sticksPressDirectionKeysPastTheThreshold() {
        let halfway = ControllerState(leftStick: .init(normalizedX: 0.4, normalizedY: 0.4))
        #expect(mapping.keys(for: halfway).isEmpty)

        let upRight = ControllerState(leftStick: .init(normalizedX: 0.7, normalizedY: 0.7))
        #expect(mapping.keys(for: upRight) == [CGKeyCode(kVK_ANSI_W), CGKeyCode(kVK_ANSI_D)])

        let downLeft = ControllerState(rightStick: .init(normalizedX: -1, normalizedY: -1))
        #expect(mapping.keys(for: downLeft) == [CGKeyCode(kVK_ANSI_K), CGKeyCode(kVK_ANSI_J)])
    }

    @Test func triggersPressPastHalfway() {
        #expect(mapping.keys(for: ControllerState(leftTrigger: 100)).isEmpty)
        #expect(mapping.keys(for: ControllerState(leftTrigger: 255, rightTrigger: 128)) == [CGKeyCode(kVK_ANSI_Q), CGKeyCode(kVK_ANSI_O)])
    }

    @Test func everyControlHasItsOwnKey() {
        let all = mapping.buttons.map(\.1)
            + [mapping.leftStick, mapping.rightStick].flatMap { [$0.up, $0.down, $0.left, $0.right] }
            + [mapping.leftTrigger, mapping.rightTrigger]
        #expect(Set(all).count == all.count)
    }
}
#endif
