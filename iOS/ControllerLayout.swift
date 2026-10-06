import CoreGraphics

/// Which controller the phone acts as.
enum ControllerKind: String, CaseIterable, Identifiable {
    /// Two sticks, A/B/X/Y, shoulders and triggers. No tilt.
    case classic
    /// A Wii Remote held sideways, steered by tilting the phone (Mario Kart). For Dolphin.
    case wiiRemote
    /// A Wii Remote pointed at the TV: the screen turns upright and the phone is held in one hand like a
    /// real remote, its top toward the TV, to aim Dolphin's pointer (Wii Party, the Wii Menu). For Dolphin.
    case wiiPointer
    /// A single right Joy-Con held sideways, as a small controller with SL and SR on top, steered by
    /// tilting (Mario Kart 8). For Eden.
    case joyConSideways
    /// A single right Joy-Con held upright in one hand, its top toward the TV (Switch Sports). For Eden.
    case joyConUpright

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: "Classic Controller"
        case .wiiRemote: "Wii Remote (sideways)"
        case .wiiPointer: "Wii Remote (pointing)"
        case .joyConSideways: "Joy-Con (sideways)"
        case .joyConUpright: "Joy-Con (upright)"
        }
    }

    /// The Wii Remotes and Joy-Cons send the phone's motion.
    var usesMotion: Bool { self != .classic }

    /// The pointing Wii Remote and the upright Joy-Con are held upright. The others are held in landscape.
    var isUpright: Bool { self == .wiiPointer || self == .joyConUpright }

    /// Held sideways like a steering wheel, so the screen shows how far the phone is turned.
    var isSteered: Bool { self == .wiiRemote || self == .joyConSideways }
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
        case wiiDpad, wiiA, wiiB, wiiOne, wiiTwo, wiiMinus, wiiHome, wiiPlus, wiiRecenter
        // The Wii Remote pointed at the TV, held upright.
        case pointDpad, pointA, pointB, pointOne, pointTwo, pointMinus, pointHome, pointPlus, pointRecenter
        // A right Joy-Con held sideways.
        case joyStick, joyButtons, joySL, joySR, joyPlus, joyHome, joyR, joyZR, joyStickPress
        // A right Joy-Con held upright.
        case joyUprightStick, joyUprightButtons, joyUprightSL, joyUprightSR, joyUprightPlus, joyUprightHome
        case joyUprightR, joyUprightZR, joyUprightStickPress

        var id: Self { self }

        var kind: ControllerKind {
            switch self {
            case .leftStick, .rightStick, .dpad, .faceButtons, .leftTrigger, .leftShoulder, .rightShoulder,
                 .rightTrigger, .view, .menu, .home, .leftStickPress, .rightStickPress:
                .classic
            case .wiiDpad, .wiiA, .wiiB, .wiiOne, .wiiTwo, .wiiMinus, .wiiHome, .wiiPlus, .wiiRecenter:
                .wiiRemote
            case .pointDpad, .pointA, .pointB, .pointOne, .pointTwo, .pointMinus, .pointHome, .pointPlus,
                 .pointRecenter:
                .wiiPointer
            case .joyStick, .joyButtons, .joySL, .joySR, .joyPlus, .joyHome, .joyR, .joyZR, .joyStickPress:
                .joyConSideways
            case .joyUprightStick, .joyUprightButtons, .joyUprightSL, .joyUprightSR, .joyUprightPlus,
                 .joyUprightHome, .joyUprightR, .joyUprightZR, .joyUprightStickPress:
                .joyConUpright
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
            case .wiiRecenter, .pointRecenter: "Center (recenters the pointer)"
            case .pointDpad: "D-pad"
            case .pointA: "A"
            case .pointB: "B"
            case .pointOne: "1"
            case .pointTwo: "2"
            case .pointMinus: "−"
            case .pointHome: "Home"
            case .pointPlus: "+"
            case .joyStick, .joyUprightStick: "Stick"
            case .joyButtons, .joyUprightButtons: "A B X Y"
            case .joySL, .joyUprightSL: "SL"
            case .joySR, .joyUprightSR: "SR"
            case .joyPlus, .joyUprightPlus: "+"
            case .joyHome, .joyUprightHome: "Home"
            case .joyR, .joyUprightR: "R"
            case .joyZR, .joyUprightZR: "ZR"
            case .joyStickPress, .joyUprightStickPress: "Stick click"
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
            case .wiiRecenter: Placement(center: CGPoint(x: 0.5, y: 0.8), scale: 1.2)
            // Pointing, upright, top to bottom as on the remote: the D-pad, A big under the thumb and
            // B below it (on the remote it's the trigger behind A), −, Home, +, then 1 and 2. Center
            // next to B, in reach of the thumb.
            case .pointDpad: Placement(center: CGPoint(x: 0.5, y: 0.2))
            case .pointA: Placement(center: CGPoint(x: 0.5, y: 0.43), scale: 1.8)
            case .pointB: Placement(center: CGPoint(x: 0.5, y: 0.6), scale: 1.4)
            case .pointRecenter: Placement(center: CGPoint(x: 0.84, y: 0.6), scale: 1.2)
            case .pointMinus: Placement(center: CGPoint(x: 0.28, y: 0.74))
            case .pointHome: Placement(center: CGPoint(x: 0.5, y: 0.74))
            case .pointPlus: Placement(center: CGPoint(x: 0.72, y: 0.74))
            case .pointOne: Placement(center: CGPoint(x: 0.5, y: 0.85))
            case .pointTwo: Placement(center: CGPoint(x: 0.5, y: 0.94))
            // Joy-Con sideways, as it lies in the hands: the stick under the left thumb, the buttons under
            // the right, SL and SR as shoulder buttons, + and Home in the middle. R and ZR sit on the back
            // of a sideways Joy-Con, so they start hidden, like the stick click.
            case .joyStick: Placement(center: CGPoint(x: 0.18, y: 0.56))
            case .joyButtons: Placement(center: CGPoint(x: 0.82, y: 0.56))
            case .joySL: Placement(center: CGPoint(x: 0.1, y: 0.14), scale: 1.3)
            case .joySR: Placement(center: CGPoint(x: 0.9, y: 0.14), scale: 1.3)
            case .joyHome: Placement(center: CGPoint(x: 0.42, y: 0.5))
            case .joyPlus: Placement(center: CGPoint(x: 0.58, y: 0.5))
            case .joyR: Placement(center: CGPoint(x: 0.42, y: 0.84), isShown: false)
            case .joyZR: Placement(center: CGPoint(x: 0.58, y: 0.84), isShown: false)
            case .joyStickPress: Placement(center: CGPoint(x: 0.34, y: 0.84), isShown: false)
            // Joy-Con upright, top to bottom as on the Joy-Con: R and ZR, +, the buttons, the stick, Home.
            // SL and SR are on its rail, out of the thumb's reach, so they start hidden.
            case .joyUprightR: Placement(center: CGPoint(x: 0.35, y: 0.14), scale: 1.2)
            case .joyUprightZR: Placement(center: CGPoint(x: 0.65, y: 0.14), scale: 1.2)
            case .joyUprightPlus: Placement(center: CGPoint(x: 0.8, y: 0.24))
            case .joyUprightButtons: Placement(center: CGPoint(x: 0.5, y: 0.4), scale: 1.3)
            case .joyUprightStick: Placement(center: CGPoint(x: 0.5, y: 0.66), scale: 1.2)
            case .joyUprightHome: Placement(center: CGPoint(x: 0.5, y: 0.84))
            case .joyUprightSL: Placement(center: CGPoint(x: 0.12, y: 0.5), isShown: false)
            case .joyUprightSR: Placement(center: CGPoint(x: 0.88, y: 0.5), isShown: false)
            case .joyUprightStickPress: Placement(center: CGPoint(x: 0.8, y: 0.66), isShown: false)
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
