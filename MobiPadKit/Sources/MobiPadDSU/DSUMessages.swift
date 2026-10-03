import Foundation
import MobiPadProtocol

/// The DSU ("cemuhook") protocol, which Dolphin and other emulators use to read controllers
/// from another program over UDP. See docs/research/virtual-hid-macos.md.
///
/// Every message is a 16-byte header, a 4-byte message type and a payload. All multi-byte
/// fields are little-endian. Message sizes must match exactly: Dolphin drops longer messages.
public enum DSU {
    public static let defaultPort: UInt16 = 26760
    public static let slotCount = 4

    static let protocolVersion: UInt16 = 1001
    static let headerSize = 16
    static let clientMagic = Array("DSUC".utf8)
    static let serverMagic = Array("DSUS".utf8)

    enum MessageType: UInt32 {
        case version = 0x10_0000
        /// Client: which slots are connected? Server: one reply per requested slot.
        case portInfo = 0x10_0001
        /// Client: subscribe to controller data. Server: controller data.
        case padData = 0x10_0002
    }

    /// Fake but stable MAC address per slot ("MP" + slot), since some clients subscribe by MAC.
    static func macAddress(slot: Int) -> [UInt8] {
        [0x4D, 0x50, 0, 0, 0, UInt8(slot)]
    }
}

// MARK: - Client requests

extension DSU {
    enum Request: Equatable {
        case version
        case listPorts(slots: [Int])
        case subscribe(slots: Set<Int>)

        struct ParseError: Error {}

        init(decoding data: Data) throws(ParseError) {
            let bytes = [UInt8](data)
            guard bytes.count >= headerSize + 4,
                  Array(bytes[0..<4]) == clientMagic,
                  bytes.readLittleEndian(UInt16.self, at: 4) <= protocolVersion
            else { throw ParseError() }

            let length = headerSize + Int(bytes.readLittleEndian(UInt16.self, at: 6))
            guard length <= bytes.count else { throw ParseError() }
            var unsigned = Array(bytes[0..<length])
            unsigned.replaceSubrange(8..<12, with: [0, 0, 0, 0])
            guard CRC32.checksum(unsigned) == bytes.readLittleEndian(UInt32.self, at: 8) else { throw ParseError() }

            switch MessageType(rawValue: bytes.readLittleEndian(UInt32.self, at: 16)) {
            case .version:
                self = .version
            case .portInfo:
                guard length >= 24 else { throw ParseError() }
                let count = Int(bytes.readLittleEndian(Int32.self, at: 20))
                guard (0...slotCount).contains(count), length >= 24 + count else { throw ParseError() }
                self = .listPorts(slots: bytes[24..<24 + count].map(Int.init).filter { $0 < slotCount })
            case .padData:
                guard length >= 28 else { throw ParseError() }
                let flags = bytes[20]
                var slots = Set<Int>()
                if flags == 0 {
                    slots = Set(0..<slotCount)
                }
                if flags & 0x01 != 0, bytes[21] < slotCount {
                    slots.insert(Int(bytes[21]))
                }
                if flags & 0x02 != 0, let slot = (0..<slotCount).first(where: { macAddress(slot: $0) == Array(bytes[22..<28]) }) {
                    slots.insert(slot)
                }
                self = .subscribe(slots: slots)
            case nil:
                throw ParseError()
            }
        }
    }
}

// MARK: - Server messages

extension DSU {
    static func versionResponse(serverID: UInt32) -> Data {
        var payload: [UInt8] = []
        payload.appendLittleEndian(protocolVersion)
        payload += [0, 0]
        return message(.version, payload: payload, serverID: serverID)
    }

    static func portInfo(slot: Int, isConnected: Bool, serverID: UInt32) -> Data {
        message(.portInfo, payload: slotInfo(slot: slot, isConnected: isConnected) + [0], serverID: serverID)
    }

    /// Motion is zero while the phone doesn't send any (the Classic Controller layout).
    static func padData(
        slot: Int,
        state: ControllerState,
        packetCounter: UInt32,
        timestampMicroseconds: UInt64,
        serverID: UInt32
    ) -> Data {
        let buttons = state.buttons
        var payload = slotInfo(slot: slot, isConnected: true)
        payload.append(1) // active
        payload.appendLittleEndian(packetCounter)
        payload.append(bitmask(buttons, bits: buttonBits1))
        payload.append(bitmask(buttons, bits: buttonBits2)
            | (state.leftTrigger > 0 ? 0x01 : 0)
            | (state.rightTrigger > 0 ? 0x02 : 0))
        payload.append(buttons.contains(.home) ? 1 : 0) // PS
        payload.append(0) // touchpad button
        payload.append(stickByte(state.leftStick.x))
        payload.append(stickByte(state.leftStick.y))
        payload.append(stickByte(state.rightStick.x))
        payload.append(stickByte(state.rightStick.y))
        // Dolphin reads the face buttons, D-pad and shoulders from these pressure bytes,
        // not from the bitmasks above.
        payload += analogButtonOrder.map { buttons.contains($0) ? 255 : 0 }
        payload.append(state.rightTrigger)
        payload.append(state.leftTrigger)
        payload += [UInt8](repeating: 0, count: 12) // two inactive touches
        payload.appendLittleEndian(timestampMicroseconds)
        for value in motionFields(state.motion) {
            payload.appendLittleEndian(value.bitPattern)
        }
        return message(.padData, payload: payload, serverID: serverID)
    }

    /// Button mapping by position: A is the bottom face button, which DSU calls Cross.
    static let buttonBits1: [(ControllerState.Buttons, UInt8)] = [
        (.view, 0x01), // Share
        (.leftStickPress, 0x02),
        (.rightStickPress, 0x04),
        (.menu, 0x08), // Options
        (.dpadUp, 0x10),
        (.dpadRight, 0x20),
        (.dpadDown, 0x40),
        (.dpadLeft, 0x80),
    ]

    static let buttonBits2: [(ControllerState.Buttons, UInt8)] = [
        (.leftShoulder, 0x04), // L1
        (.rightShoulder, 0x08), // R1
        (.y, 0x10), // Triangle
        (.b, 0x20), // Circle
        (.a, 0x40), // Cross
        (.x, 0x80), // Square
    ]

    static let analogButtonOrder: [ControllerState.Buttons] = [
        .dpadLeft, .dpadDown, .dpadRight, .dpadUp,
        .x, .a, .b, .y, // Square, Cross, Circle, Triangle
        .rightShoulder, .leftShoulder,
    ]

    /// The DSU motion fields in packet order: accelerometer x, y, z (g), then gyro pitch, yaw, roll (°/s).
    ///
    /// Dolphin reads accelerometer x as left, -y as up and z as forward, and gyro pitch as nose up,
    /// yaw as nose right and roll as right side down (DualShockUDPClient.cpp). `Motion` uses
    /// x = right, y = forward (the top edge of the screen), z = up (out of the screen).
    static func motionFields(_ motion: ControllerState.Motion?) -> [Float] {
        guard let motion else { return [0, 0, 0, 0, 0, 0] }
        let acceleration = motion.acceleration
        let rotation = motion.rotationRate
        return [
            -acceleration.x, -acceleration.z, acceleration.y,
            // Turning around x lifts the top edge; around z, counterclockwise turns it left;
            // around y, the right edge goes down.
            rotation.x, -rotation.z, rotation.y,
        ]
    }

    /// Maps -32767...32767 to 1...255 with 128 as center. Positive y is up in both.
    static func stickByte(_ value: Int16) -> UInt8 {
        UInt8(128 + Int(value) * 127 / Int(Int16.max))
    }

    private static func bitmask(_ buttons: ControllerState.Buttons, bits: [(ControllerState.Buttons, UInt8)]) -> UInt8 {
        bits.reduce(0) { mask, entry in buttons.contains(entry.0) ? mask | entry.1 : mask }
    }

    /// Slot, state, model, connection type, MAC address, battery: shared by port info and pad data.
    private static func slotInfo(slot: Int, isConnected: Bool) -> [UInt8] {
        guard isConnected else {
            return [UInt8(slot)] + [UInt8](repeating: 0, count: 10)
        }
        let connected: UInt8 = 2, fullGyro: UInt8 = 2, bluetooth: UInt8 = 2, batteryUnknown: UInt8 = 0
        return [UInt8(slot), connected, fullGyro, bluetooth] + macAddress(slot: slot) + [batteryUnknown]
    }

    static func message(_ type: MessageType, payload: [UInt8], serverID: UInt32, magic: [UInt8] = serverMagic) -> Data {
        var bytes = magic
        bytes.appendLittleEndian(protocolVersion)
        bytes.appendLittleEndian(UInt16(4 + payload.count))
        bytes.appendLittleEndian(UInt32(0)) // CRC, filled in below
        bytes.appendLittleEndian(serverID)
        bytes.appendLittleEndian(type.rawValue)
        bytes += payload
        withUnsafeBytes(of: CRC32.checksum(bytes).littleEndian) { bytes.replaceSubrange(8..<12, with: $0) }
        return Data(bytes)
    }
}

extension [UInt8] {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func readLittleEndian<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        self[offset..<offset + MemoryLayout<T>.size].reversed().reduce(T.zero) { ($0 << 8) | T(truncatingIfNeeded: $1) }
    }
}
