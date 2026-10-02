import Foundation

extension ControllerState.Motion {
    /// Which way round the phone is held in landscape.
    public enum Landscape: Sendable {
        /// The top of the phone (the end with the camera) is on the left. UIKit's `landscapeRight`.
        case topOnLeft
        /// The top of the phone is on the right. UIKit's `landscapeLeft`.
        case topOnRight
    }

    /// Converts Core Motion's device motion into the landscape controller's frame.
    ///
    /// Core Motion uses the phone's portrait axes (x to the right edge, y to the top, z out of the
    /// screen), reports gravity as pointing toward the ground, and measures rotation in radians per
    /// second. An accelerometer measures the opposite of gravity plus the user's acceleration, which is
    /// what `acceleration` holds.
    ///
    /// - Parameters:
    ///   - gravity: Core Motion's `gravity`, in g.
    ///   - userAcceleration: Core Motion's `userAcceleration`, in g.
    ///   - rotationRate: Core Motion's `rotationRate`, in radians per second.
    public init(gravity: Vector, userAcceleration: Vector, rotationRate: Vector, landscape: Landscape) {
        let measured = Vector(
            x: -(gravity.x + userAcceleration.x),
            y: -(gravity.y + userAcceleration.y),
            z: -(gravity.z + userAcceleration.z)
        )
        let degreesPerRadian = Float(180 / Double.pi)
        let rotation = Vector(
            x: rotationRate.x * degreesPerRadian,
            y: rotationRate.y * degreesPerRadian,
            z: rotationRate.z * degreesPerRadian
        )
        self.init(
            acceleration: measured.landscape(landscape),
            rotationRate: rotation.landscape(landscape)
        )
    }
}

private extension ControllerState.Motion.Vector {
    /// The same vector in landscape axes: x to the right edge of the screen, y to the top edge.
    func landscape(_ landscape: ControllerState.Motion.Landscape) -> Self {
        switch landscape {
        // The portrait top points left, so the portrait right edge points up.
        case .topOnLeft: Self(x: -y, y: x, z: z)
        // The portrait top points right, so the portrait left edge points up.
        case .topOnRight: Self(x: y, y: -x, z: z)
        }
    }
}
