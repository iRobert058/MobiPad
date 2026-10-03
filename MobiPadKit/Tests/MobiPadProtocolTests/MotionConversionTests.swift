import Foundation
import Testing
import MobiPadProtocol

/// Poses are described the way Core Motion would report them: in the phone's portrait axes
/// (x to the right edge, y to the top, z out of the screen), with gravity pointing at the ground.
struct MotionConversionTests {
    typealias Motion = ControllerState.Motion
    typealias Vector = Motion.Vector

    static func motion(gravity: Vector, user: Vector = .zero, rotation: Vector = .zero, _ orientation: Motion.Orientation) -> Motion {
        Motion(gravity: gravity, userAcceleration: user, rotationRate: rotation, orientation: orientation)
    }

    static func expectClose(_ vector: Vector, _ expected: Vector, sourceLocation: SourceLocation = #_sourceLocation) {
        for (actual, wanted) in [(vector.x, expected.x), (vector.y, expected.y), (vector.z, expected.z)] {
            #expect(abs(actual - wanted) < 0.001, "\(vector) isn't \(expected)", sourceLocation: sourceLocation)
        }
    }

    @Test(arguments: [Motion.Orientation.portrait, .topOnLeft, .topOnRight])
    func lyingFaceUpMeasuresOneGOutOfTheScreen(orientation: Motion.Orientation) {
        Self.expectClose(Self.motion(gravity: .init(x: 0, y: 0, z: -1), orientation).acceleration, .init(x: 0, y: 0, z: 1))
    }

    /// Upright, the screen's axes are the phone's own, so Core Motion's axes stay as they are.
    @Test func portraitKeepsThePhonesAxes() {
        let motion = Self.motion(gravity: .init(x: 0, y: -1, z: 0), rotation: .init(x: 1, y: 0, z: 0), .portrait)
        Self.expectClose(motion.acceleration, .init(x: 0, y: 1, z: 0))
        Self.expectClose(motion.rotationRate, .init(x: Float(180 / Double.pi), y: 0, z: 0))
    }

    /// Held up in front of the player like a steering wheel: the top edge of the landscape screen
    /// points at the ceiling, whichever end the camera is on.
    @Test func heldUprightMeasuresOneGTowardTheTopEdge() {
        // Camera on the left: the portrait right edge points up, so gravity points to the portrait left.
        Self.expectClose(Self.motion(gravity: .init(x: -1, y: 0, z: 0), .topOnLeft).acceleration, .init(x: 0, y: 1, z: 0))
        // Camera on the right: the portrait left edge points up.
        Self.expectClose(Self.motion(gravity: .init(x: 1, y: 0, z: 0), .topOnRight).acceleration, .init(x: 0, y: 1, z: 0))
    }

    /// Turning the wheel clockwise (as the player sees it) lowers the right end, so "up" leans
    /// toward the left edge: x goes negative.
    @Test func steeringClockwiseLeansTowardTheLeftEdge() {
        let angle = Float.pi / 6 // 30°
        // Turning the phone clockwise by 30° turns gravity 30° counterclockwise in the phone's axes.
        let gravity = Vector(x: -cos(angle), y: -sin(angle), z: 0)
        Self.expectClose(Self.motion(gravity: gravity, .topOnLeft).acceleration, .init(x: -sin(angle), y: cos(angle), z: 0))
    }

    @Test func addsTheUsersOwnAcceleration() {
        // Lifted quickly while face up: Core Motion reports the extra acceleration along -z.
        let motion = Self.motion(gravity: .init(x: 0, y: 0, z: -1), user: .init(x: 0, y: 0, z: -0.5), .topOnLeft)
        Self.expectClose(motion.acceleration, .init(x: 0, y: 0, z: 1.5))
    }

    /// A sideways Wii Remote's IR end is the phone's left edge, so what the phone measures toward its
    /// left edge is what the remote measures toward its front (y).
    @Test func turnedSidewaysMakesTheLeftEdgeTheFront() {
        let motion = Motion(acceleration: .init(x: -1, y: 0.5, z: 0.25), rotationRate: .init(x: 10, y: 20, z: 30))
        Self.expectClose(motion.turnedSideways.acceleration, .init(x: 0.5, y: 1, z: 0.25))
        Self.expectClose(motion.turnedSideways.rotationRate, .init(x: 20, y: -10, z: 30))
    }

    @Test func steeringAngleIsClockwiseAndNilWhenFlat() throws {
        let angle = Float.pi / 6
        let turned = Motion(acceleration: .init(x: -sin(angle), y: cos(angle), z: 0), rotationRate: .zero)
        #expect(abs(try #require(turned.steeringAngle) - Double.pi / 6) < 0.0001)
        #expect(Motion(acceleration: .init(x: 0, y: 0, z: 1), rotationRate: .zero).steeringAngle == nil)
    }

    @Test func rotationIsInDegreesPerSecondInTheScreensAxes() {
        let oneRadian = Float(180 / Double.pi)
        // Spinning in the plane of the screen is the same in portrait and landscape.
        Self.expectClose(
            Self.motion(gravity: .zero, rotation: .init(x: 0, y: 0, z: 1), .topOnRight).rotationRate,
            .init(x: 0, y: 0, z: oneRadian)
        )
        // Around the portrait x axis, which points to the top edge with the camera on the left.
        Self.expectClose(
            Self.motion(gravity: .zero, rotation: .init(x: 1, y: 0, z: 0), .topOnLeft).rotationRate,
            .init(x: 0, y: oneRadian, z: 0)
        )
        // Around the portrait y axis, which points left with the camera on the left.
        Self.expectClose(
            Self.motion(gravity: .zero, rotation: .init(x: 0, y: 1, z: 0), .topOnLeft).rotationRate,
            .init(x: -oneRadian, y: 0, z: 0)
        )
    }
}
