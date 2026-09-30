import Foundation

/// A message between the iPhone app and the Mac companion app, one per UDP datagram.
///
/// Every message starts with a 4-byte header: magic `"MP"`, protocol version, message type.
/// Multi-byte fields are big-endian. Payloads:
///
/// | Type | Message | Payload                                                                      |
/// |------|---------|------------------------------------------------------------------------------|
/// | 1    | state   | sequence u32, buttons u16, left x/y, right x/y (i16 each), triggers (u8 each) |
/// | 2    | hello   | client ID (16-byte UUID), device name (UTF-8, rest of the datagram)          |
/// | 3    | welcome | slot u8                                                                      |
/// | 4    | full    | none                                                                         |
/// | 5    | goodbye | none                                                                         |
/// | 6    | ping    | token u64                                                                    |
/// | 7    | pong    | token u64                                                                    |
public enum Message: Equatable, Sendable {
    /// Phone → Mac: a complete controller snapshot. The phone sends snapshots rather than
    /// events, so a lost datagram is corrected by the next one and no button can get stuck.
    case state(sequence: UInt32, ControllerState)
    /// Phone → Mac: asks for a controller slot. Repeated until the Mac answers.
    /// The client ID stays the same across launches, so a phone gets its slot back after a dropout.
    case hello(clientID: UUID, name: String)
    /// Mac → phone: the phone controls this slot (player number minus one).
    case welcome(slot: UInt8)
    /// Mac → phone: every slot is taken.
    case full
    /// Phone → Mac: the user disconnected (FR-02).
    case goodbye
    /// Mac → phone, answered with a pong carrying the same token. Measures latency and
    /// tells the phone the Mac is still there.
    case ping(token: UInt64)
    case pong(token: UInt64)

    public static let magic: [UInt8] = Array("MP".utf8)
    public static let version: UInt8 = 1
    public static let maxNameLength = 32

    private enum MessageType: UInt8 {
        case state = 1, hello, welcome, full, goodbye, ping, pong
    }

    /// Whether `sequence` was sent after `other`, allowing for wrap-around. UDP can reorder
    /// datagrams, so the Mac drops states that are older than the last one it applied.
    public static func isSequence(_ sequence: UInt32, newerThan other: UInt32) -> Bool {
        let distance = sequence &- other
        return distance != 0 && distance < UInt32(1) << 31
    }

    public func encoded() -> Data {
        var data = Data(Self.magic + [Self.version])
        switch self {
        case .state(let sequence, let state):
            data.append(MessageType.state.rawValue)
            data.appendBigEndian(sequence)
            data.appendBigEndian(state.buttons.rawValue)
            data.appendBigEndian(state.leftStick.x)
            data.appendBigEndian(state.leftStick.y)
            data.appendBigEndian(state.rightStick.x)
            data.appendBigEndian(state.rightStick.y)
            data.append(state.leftTrigger)
            data.append(state.rightTrigger)
        case .hello(let clientID, let name):
            data.append(MessageType.hello.rawValue)
            withUnsafeBytes(of: clientID.uuid) { data.append(contentsOf: $0) }
            data.append(contentsOf: name.prefix(Self.maxNameLength).utf8)
        case .welcome(let slot):
            data.append(MessageType.welcome.rawValue)
            data.append(slot)
        case .full:
            data.append(MessageType.full.rawValue)
        case .goodbye:
            data.append(MessageType.goodbye.rawValue)
        case .ping(let token):
            data.append(MessageType.ping.rawValue)
            data.appendBigEndian(token)
        case .pong(let token):
            data.append(MessageType.pong.rawValue)
            data.appendBigEndian(token)
        }
        return data
    }

    public init(decoding data: Data) throws(ParseError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw .tooShort }
        guard Array(bytes[0..<2]) == Self.magic else { throw .badMagic }
        guard bytes[2] == Self.version else { throw .unsupportedVersion(bytes[2]) }
        guard let type = MessageType(rawValue: bytes[3]) else { throw .unknownMessageType(bytes[3]) }

        var reader = BigEndianReader(bytes: bytes, offset: 4)
        func requireLength(_ payloadLength: Int) throws(ParseError) {
            guard bytes.count == 4 + payloadLength else { throw .wrongLength }
        }

        switch type {
        case .state:
            try requireLength(16)
            self = .state(sequence: reader.read(UInt32.self), ControllerState(
                buttons: .init(rawValue: reader.read(UInt16.self)),
                leftStick: .init(x: reader.read(Int16.self), y: reader.read(Int16.self)),
                rightStick: .init(x: reader.read(Int16.self), y: reader.read(Int16.self)),
                leftTrigger: reader.read(UInt8.self),
                rightTrigger: reader.read(UInt8.self)
            ))
        case .hello:
            guard bytes.count >= 20 else { throw .wrongLength }
            let uuid = UUID(uuid: (
                bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15], bytes[16], bytes[17], bytes[18], bytes[19]
            ))
            let name = String(decoding: bytes[20...], as: UTF8.self)
            self = .hello(clientID: uuid, name: String(name.prefix(Self.maxNameLength)))
        case .welcome:
            try requireLength(1)
            self = .welcome(slot: bytes[4])
        case .full:
            try requireLength(0)
            self = .full
        case .goodbye:
            try requireLength(0)
            self = .goodbye
        case .ping:
            try requireLength(8)
            self = .ping(token: reader.read(UInt64.self))
        case .pong:
            try requireLength(8)
            self = .pong(token: reader.read(UInt64.self))
        }
    }

    public enum ParseError: Error, Equatable {
        case tooShort
        case badMagic
        case unsupportedVersion(UInt8)
        case unknownMessageType(UInt8)
        case wrongLength
    }
}

private struct BigEndianReader {
    let bytes: [UInt8]
    var offset: Int

    /// Callers must have checked that enough bytes remain.
    mutating func read<T: FixedWidthInteger>(_: T.Type) -> T {
        let size = MemoryLayout<T>.size
        let value = bytes[offset..<offset + size].reduce(T.zero) { ($0 << 8) | T(truncatingIfNeeded: $1) }
        offset += size
        return value
    }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
