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

    /// The emulated Wii Remote's acceleration with Dolphin's "Sideways Wii Remote" option on:
    /// Dolphin's frame is x = left, y = backward, z = up, rotated a quarter turn around z.
    var sidewaysWiiRemote: (left: Float, backward: Float, up: Float) {
        let device = (x: left, y: -forward, z: up)
        return (left: device.y, backward: -device.x, up: device.z)
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
    /// edge up, should look exactly like that to Dolphin.
    @Test func heldUprightIsASidewaysRemoteWithItsLeftSideDown() throws {
        let remote = try Self.dolphinMotion(Self.still(0, 1, 0)).sidewaysWiiRemote
        #expect(remote.left == -1) // the accelerometer reads 1 g toward the remote's right side
        #expect(remote.backward == 0 && remote.up == 0)
    }

    /// Turning the wheel clockwise lifts the phone's left end, which is the Wii Remote's IR end.
    @Test func steeringClockwiseLiftsTheIREnd() throws {
        let angle = Float.pi / 6
        let remote = try Self.dolphinMotion(Self.still(-sin(angle), cos(angle), 0)).sidewaysWiiRemote
        #expect(remote.backward < 0) // the reading leans forward, toward the IR end
        #expect(abs(remote.backward + sin(angle)) < 0.0001)
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
