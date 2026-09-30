#if os(macOS)
import Carbon.HIToolbox
import CoreGraphics
import MobiPadProtocol

/// Which keys a controller state holds down, for emulators without DSU support (such as Ryujinx).
///
/// The defaults follow Ryujinx's default keyboard layout, matched by button position: the bottom
/// face button (A on MobiPad) is the Switch's B. If an emulator uses other keys, rebind them there
/// by pressing the buttons on the phone.
public struct KeyboardMapping: Sendable {
    public struct Directions: Sendable {
        public var up: CGKeyCode
        public var down: CGKeyCode
        public var left: CGKeyCode
        public var right: CGKeyCode
    }

    public var buttons: [(ControllerState.Buttons, CGKeyCode)]
    public var leftStick: Directions
    public var rightStick: Directions
    public var leftTrigger: CGKeyCode
    public var rightTrigger: CGKeyCode
    /// How far a stick must be pushed before its direction key goes down, from 0 to 1.
    public var stickThreshold = 0.5

    public static let `default` = KeyboardMapping(
        buttons: [
            (.a, key(kVK_ANSI_X)), // bottom: Switch B
            (.b, key(kVK_ANSI_Z)), // right: Switch A
            (.x, key(kVK_ANSI_V)), // left: Switch Y
            (.y, key(kVK_ANSI_C)), // top: Switch X
            (.leftShoulder, key(kVK_ANSI_E)),
            (.rightShoulder, key(kVK_ANSI_U)),
            (.leftStickPress, key(kVK_ANSI_F)),
            (.rightStickPress, key(kVK_ANSI_H)),
            (.menu, key(kVK_ANSI_Equal)), // Plus
            (.view, key(kVK_ANSI_Minus)), // Minus
            (.dpadUp, key(kVK_UpArrow)),
            (.dpadDown, key(kVK_DownArrow)),
            (.dpadLeft, key(kVK_LeftArrow)),
            (.dpadRight, key(kVK_RightArrow)),
        ],
        leftStick: Directions(up: key(kVK_ANSI_W), down: key(kVK_ANSI_S), left: key(kVK_ANSI_A), right: key(kVK_ANSI_D)),
        rightStick: Directions(up: key(kVK_ANSI_I), down: key(kVK_ANSI_K), left: key(kVK_ANSI_J), right: key(kVK_ANSI_L)),
        leftTrigger: key(kVK_ANSI_Q),
        rightTrigger: key(kVK_ANSI_O)
    )

    public func keys(for state: ControllerState) -> Set<CGKeyCode> {
        var keys = Set(buttons.filter { state.buttons.contains($0.0) }.map(\.1))
        keys.formUnion(directionKeys(state.leftStick, leftStick))
        keys.formUnion(directionKeys(state.rightStick, rightStick))
        if state.leftTrigger >= 128 { keys.insert(leftTrigger) }
        if state.rightTrigger >= 128 { keys.insert(rightTrigger) }
        return keys
    }

    private func directionKeys(_ stick: ControllerState.Stick, _ directions: Directions) -> [CGKeyCode] {
        let threshold = Int(stickThreshold * Double(Int16.max))
        var keys: [CGKeyCode] = []
        if Int(stick.y) >= threshold { keys.append(directions.up) }
        if Int(stick.y) <= -threshold { keys.append(directions.down) }
        if Int(stick.x) <= -threshold { keys.append(directions.left) }
        if Int(stick.x) >= threshold { keys.append(directions.right) }
        return keys
    }

    private static func key(_ code: Int) -> CGKeyCode {
        CGKeyCode(code)
    }
}
#endif
