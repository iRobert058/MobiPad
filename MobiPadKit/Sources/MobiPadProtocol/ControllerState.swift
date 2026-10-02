import Foundation

/// A snapshot of every control on the virtual controller.
///
/// The phone sends complete snapshots rather than individual events, so a lost
/// packet is corrected by the next one and no button can get stuck.
/// Values are stored at wire precision, so encoding and decoding is lossless.
public struct ControllerState: Equatable, Sendable {
    public var buttons: Buttons
    public var leftStick: Stick
    public var rightStick: Stick
    /// 0 = released, 255 = fully pressed.
    public var leftTrigger: UInt8
    public var rightTrigger: UInt8
    /// The phone's motion sensors, when the player uses tilt (Wii Remote mode). Nil otherwise.
    public var motion: Motion?

    public init(
        buttons: Buttons = [],
        leftStick: Stick = .centered,
        rightStick: Stick = .centered,
        leftTrigger: UInt8 = 0,
        rightTrigger: UInt8 = 0,
        motion: Motion? = nil
    ) {
        self.buttons = buttons
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.motion = motion
    }
}

extension ControllerState {
    public struct Buttons: OptionSet, Hashable, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let a = Buttons(rawValue: 1 << 0)
        public static let b = Buttons(rawValue: 1 << 1)
        public static let x = Buttons(rawValue: 1 << 2)
        public static let y = Buttons(rawValue: 1 << 3)
        public static let leftShoulder = Buttons(rawValue: 1 << 4)
        public static let rightShoulder = Buttons(rawValue: 1 << 5)
        public static let leftStickPress = Buttons(rawValue: 1 << 6)
        public static let rightStickPress = Buttons(rawValue: 1 << 7)
        /// Start / Menu.
        public static let menu = Buttons(rawValue: 1 << 8)
        /// Select / View.
        public static let view = Buttons(rawValue: 1 << 9)
        public static let home = Buttons(rawValue: 1 << 10)
        public static let dpadUp = Buttons(rawValue: 1 << 11)
        public static let dpadDown = Buttons(rawValue: 1 << 12)
        public static let dpadLeft = Buttons(rawValue: 1 << 13)
        public static let dpadRight = Buttons(rawValue: 1 << 14)
    }

    /// An analog stick position. Positive x is right, positive y is up.
    public struct Stick: Equatable, Sendable {
        /// Axis values are symmetric around 0 so that negating an axis never overflows.
        public static let range: ClosedRange<Int16> = -Int16.max...Int16.max
        public static let centered = Stick(x: 0, y: 0)

        public var x: Int16
        public var y: Int16

        public init(x: Int16, y: Int16) {
            self.x = x.clamped(to: Self.range)
            self.y = y.clamped(to: Self.range)
        }

        /// Creates a stick position from normalized values in -1...1, as produced by touch input.
        public init(normalizedX: Double, normalizedY: Double) {
            self.init(x: Self.quantize(normalizedX), y: Self.quantize(normalizedY))
        }

        private static func quantize(_ value: Double) -> Int16 {
            guard value.isFinite else { return 0 }
            return Int16((value.clamped(to: -1...1) * Double(Int16.max)).rounded())
        }
    }
}

extension ControllerState {
    /// What the motion sensors measure, in the frame of the controller as the player holds it in
    /// landscape: x points to the right edge of the screen, y to the top edge, and z out of the screen.
    public struct Motion: Equatable, Sendable {
        /// What an accelerometer measures, in g, so +1 on z when lying face up at rest.
        public var acceleration: Vector
        /// Degrees per second around each axis, by the right-hand rule.
        public var rotationRate: Vector

        public init(acceleration: Vector, rotationRate: Vector) {
            self.acceleration = acceleration
            self.rotationRate = rotationRate
        }

        /// How far the controller is turned like a steering wheel, in radians, clockwise as the player
        /// sees it. Nil while it lies nearly flat, where the angle would only be noise.
        public var steeringAngle: Double? {
            guard hypot(acceleration.x, acceleration.y) > 0.35 else { return nil }
            return Double(atan2(-acceleration.x, acceleration.y))
        }

        public struct Vector: Equatable, Sendable {
            public static let zero = Vector(x: 0, y: 0, z: 0)

            public var x: Float
            public var y: Float
            public var z: Float

            public init(x: Float, y: Float, z: Float) {
                self.x = x
                self.y = y
                self.z = z
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
