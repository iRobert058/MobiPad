import CoreGraphics

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
}

extension ControllerLayout {
    /// The parts of the controller that move as one. The D-pad and A/B/X/Y move as a block.
    enum Control: String, CaseIterable, Codable, CodingKeyRepresentable, Identifiable {
        case leftStick, rightStick, dpad, faceButtons
        case leftTrigger, leftShoulder, rightShoulder, rightTrigger
        case view, menu, home, leftStickPress, rightStickPress

        var id: Self { self }

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
