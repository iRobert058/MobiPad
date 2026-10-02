import CoreGraphics

/// Which controller the phone acts as.
enum ControllerKind: String, CaseIterable, Identifiable {
    /// Two sticks, A/B/X/Y, shoulders and triggers. No tilt.
    case classic
    /// A Wii Remote held sideways, steered by tilting the phone. For Dolphin.
    case wiiRemote

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: "Classic Controller"
        case .wiiRemote: "Wii Remote"
        }
    }
}

/// Where each control sits on the controller screen, how big it is, and whether it's shown (UX-03).
///
/// Positions are fractions of the controller area, so a layout made on one iPhone fits any other.
struct ControllerLayout: Codable, Equatable {
    private var placements: [Control: Placement]

    static let standard = ControllerLayout(
        placements: Dictionary(uniqueKeysWithValues: Control.allCases.map { ($0, $0.standardPlacement) })
    )

    /// How far a control can shrink or grow, relative to its standard size.
    static let scales: ClosedRange<CGFloat> = 0.6...1.8

    subscript(control: Control) -> Placement {
        // A control added in a later version starts where the standard layout puts it.
        get { placements[control] ?? control.standardPlacement }
        set { placements[control] = newValue }
    }

    /// Puts one controller's controls back where the standard layout has them.
    mutating func reset(_ kind: ControllerKind) {
        for control in Control.allCases where control.kind == kind {
            placements[control] = control.standardPlacement
        }
    }
}

extension ControllerLayout {
    /// The parts of the controller that move as one. The D-pad and A/B/X/Y move as a block.
    enum Control: String, CaseIterable, Codable, CodingKeyRepresentable, Identifiable {
        case leftStick, rightStick, dpad, faceButtons
        case leftTrigger, leftShoulder, rightShoulder, rightTrigger
        case view, menu, home, leftStickPress, rightStickPress
        // The Wii Remote layout, held sideways like an NES pad.
        case wiiDpad, wiiA, wiiB, wiiOne, wiiTwo, wiiMinus, wiiHome, wiiPlus

        var id: Self { self }

        var kind: ControllerKind {
            switch self {
            case .leftStick, .rightStick, .dpad, .faceButtons, .leftTrigger, .leftShoulder, .rightShoulder,
                 .rightTrigger, .view, .menu, .home, .leftStickPress, .rightStickPress:
                .classic
            case .wiiDpad, .wiiA, .wiiB, .wiiOne, .wiiTwo, .wiiMinus, .wiiHome, .wiiPlus:
                .wiiRemote
            }
        }

        var name: String {
            switch self {
            case .leftStick: "Left stick"
            case .rightStick: "Right stick"
            case .dpad: "D-pad"
            case .faceButtons: "A B X Y"
            case .leftTrigger: "LT"
            case .leftShoulder: "LB"
            case .rightShoulder: "RB"
            case .rightTrigger: "RT"
            case .view: "View"
            case .menu: "Menu"
            case .home: "Home"
            case .leftStickPress: "L3 (left stick click)"
            case .rightStickPress: "R3 (right stick click)"
            case .wiiDpad: "D-pad"
            case .wiiA: "A"
            case .wiiB: "B"
            case .wiiOne: "1"
            case .wiiTwo: "2"
            case .wiiMinus: "−"
            case .wiiHome: "Home"
            case .wiiPlus: "+"
            }
        }

        fileprivate var standardPlacement: Placement {
            switch self {
            case .leftTrigger: Placement(center: CGPoint(x: 0.04, y: 0.12))
            case .leftShoulder: Placement(center: CGPoint(x: 0.12, y: 0.12))
            case .rightShoulder: Placement(center: CGPoint(x: 0.88, y: 0.12))
            case .rightTrigger: Placement(center: CGPoint(x: 0.96, y: 0.12))
            case .leftStick: Placement(center: CGPoint(x: 0.1, y: 0.36))
            case .dpad: Placement(center: CGPoint(x: 0.1, y: 0.76))
            case .faceButtons: Placement(center: CGPoint(x: 0.9, y: 0.42))
            case .rightStick: Placement(center: CGPoint(x: 0.9, y: 0.8))
            case .view: Placement(center: CGPoint(x: 0.44, y: 0.5))
            case .menu: Placement(center: CGPoint(x: 0.56, y: 0.5))
            // Off until the player turns them on.
            case .home: Placement(center: CGPoint(x: 0.5, y: 0.68), isShown: false)
            case .leftStickPress: Placement(center: CGPoint(x: 0.24, y: 0.36), isShown: false)
            case .rightStickPress: Placement(center: CGPoint(x: 0.76, y: 0.8), isShown: false)
            // Wii Remote: D-pad and A under the left thumb, 1 and 2 under the right, B where the left
            // index finger would find the trigger, and −, Home, + in the middle as on the remote.
            case .wiiDpad: Placement(center: CGPoint(x: 0.14, y: 0.56))
            case .wiiB: Placement(center: CGPoint(x: 0.12, y: 0.14), scale: 1.3)
            case .wiiA: Placement(center: CGPoint(x: 0.32, y: 0.56), scale: 1.2)
            case .wiiMinus: Placement(center: CGPoint(x: 0.42, y: 0.5))
            case .wiiHome: Placement(center: CGPoint(x: 0.5, y: 0.5))
            case .wiiPlus: Placement(center: CGPoint(x: 0.58, y: 0.5))
            case .wiiOne: Placement(center: CGPoint(x: 0.74, y: 0.56), scale: 1.5)
            case .wiiTwo: Placement(center: CGPoint(x: 0.9, y: 0.56), scale: 1.5)
            }
        }
    }

    struct Placement: Codable, Equatable {
        /// The control's center, as a fraction of the controller area's width and height.
        var center: CGPoint
        /// 1 is the standard size.
        var scale: CGFloat = 1
        var isShown = true
    }
}
