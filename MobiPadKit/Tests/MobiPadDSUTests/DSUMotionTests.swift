import Foundation
import MobiPadProtocol
import Testing
@testable import MobiPadDSU

/// Reads the motion in a pad data packet the way Dolphin does (DualShockUDPClient.cpp and the
/// Wii Remote's IMU groups), so these tests say what Dolphin will see.
struct DolphinMotion {
    /// Accelerometer, in g.
    var up: Float, left: Float, forward: Float
    /// Gyroscope, in °/s.
    var pitchUp: Float, yawRight: Float, rollRight: Float

    init(_ message: ServerMessage) {
        func float(at offset: Int) -> Float { Float(bitPattern: message.bytes.readLittleEndian(UInt32.self, at: offset)) }
        // The six motion floats are the last 24 bytes of the 100-byte packet.
        up = -float(at: 80) // Accel Up = -accelerometer y
        left = float(at: 76) // Accel Left = +accelerometer x
        forward = float(at: 84) // Accel Forward = +accelerometer z
        pitchUp = float(at: 88)
        yawRight = float(at: 92)
        rollRight = float(at: 96)
    }

    typealias Vector = (x: Float, y: Float, z: Float)

    /// What the Wii Remote's accelerometer reads, in Dolphin's frame: x = left, y = backward, z = up
    /// (`IMUAccelerometer::GetState`).
    var acceleration: Vector { (x: left, y: -forward, z: up) }

    /// What the Wii Remote's gyroscope reads, in the same frame (`IMUGyroscope::GetRawState`:
    /// x = Pitch Down − Pitch Up, y = Roll Left − Roll Right, z = Yaw Left − Yaw Right).
    var angularVelocity: Vector { (x: -pitchUp, y: -rollRight, z: -yawRight) }

    /// Dolphin's "Sideways Wii Remote" option: a quarter turn around z (`Wiimote::GetOrientation`).
    static func dolphinsSidewaysOption(_ vector: Vector) -> Vector {
        (x: vector.y, y: -vector.x, z: vector.z)
    }
}

struct DSUMotionTests {
    typealias Motion = ControllerState.Motion

    static func dolphinMotion(_ motion: Motion?) throws -> DolphinMotion {
        let state = ControllerState(motion: motion)
        return try DolphinMotion(ServerMessage(DSU.padData(slot: 0, state: state, packetCounter: 1, timestampMicroseconds: 0, serverID: 0)))
    }

    static func still(_ x: Float, _ y: Float, _ z: Float) -> Motion {
        Motion(acceleration: .init(x: x, y: y, z: z), rotationRate: .zero)
    }

    /// The Classic Controller layout sends no motion, and the packet stays as it was before tilt.
    @Test func noMotionSendsZeros() throws {
        let packet = DSU.padData(slot: 0, state: ControllerState(), packetCounter: 1, timestampMicroseconds: 0, serverID: 0)
        #expect([UInt8](packet)[76..<100].allSatisfy { $0 == 0 })
    }

    @Test func lyingFaceUpReadsOneGUp() throws {
        let motion = try Self.dolphinMotion(Self.still(0, 0, 1))
        #expect(motion.up == 1 && motion.left == 0 && motion.forward == 0)
    }

    /// Held up like a Wii Wheel, a sideways Wii Remote has its IR end on the left and its face toward
    /// the player, so its left side points at the floor. The phone, held the same way with its top
    /// edge up and its motion turned sideways, should look exactly like that to Dolphin.
    @Test func heldUprightIsASidewaysRemoteWithItsLeftSideDown() throws {
        let remote = try Self.dolphinMotion(Self.still(0, 1, 0).turnedSideways).acceleration
        #expect(remote.x == -1) // the accelerometer reads 1 g toward the remote's right side
        #expect(remote.y == 0 && remote.z == 0)
    }

    /// Turning the wheel clockwise lifts the phone's left end, which is the Wii Remote's IR end.
    @Test func steeringClockwiseLiftsTheIREnd() throws {
        let angle = Float.pi / 6
        let remote = try Self.dolphinMotion(Self.still(-sin(angle), cos(angle), 0).turnedSideways).acceleration
        #expect(remote.y < 0) // the reading leans forward (y is backward), toward the IR end
        #expect(abs(remote.y + sin(angle)) < 0.0001)
    }

    /// The phone turns its motion sideways itself, so Dolphin's Sideways option stays off. That has to
    /// give exactly what the option would have given.
    @Test(arguments: [
        Motion(acceleration: .init(x: 0, y: 1, z: 0), rotationRate: .init(x: 30, y: 0, z: 0)),
        Motion(acceleration: .init(x: -0.5, y: 0.7, z: 0.4), rotationRate: .init(x: -12, y: 45, z: 90)),
        Motion(acceleration: .init(x: 0.2, y: -0.3, z: 0.9), rotationRate: .init(x: 5, y: -60, z: -15)),
    ])
    func turningOnThePhoneMatchesDolphinsSidewaysOption(motion: Motion) throws {
        let turnedByPhone = try Self.dolphinMotion(motion.turnedSideways)
        let unturned = try Self.dolphinMotion(motion)
        #expect(turnedByPhone.acceleration == DolphinMotion.dolphinsSidewaysOption(unturned.acceleration))
        #expect(turnedByPhone.angularVelocity == DolphinMotion.dolphinsSidewaysOption(unturned.angularVelocity))
    }

    @Test func rotationUsesDolphinsDirections() throws {
        let around = { (x: Float, y: Float, z: Float) in
            try Self.dolphinMotion(Motion(acceleration: .zero, rotationRate: .init(x: x, y: y, z: z)))
        }
        // Around x (the right edge) lifts the top edge: nose up.
        #expect(try around(90, 0, 0).pitchUp == 90)
        // Around z (out of the screen), counterclockwise: nose left.
        #expect(try around(0, 0, 90).yawRight == -90)
        // Around y (the top edge): the right edge goes down.
        #expect(try around(0, 90, 0).rollRight == 90)
    }
}
