import Foundation

/// A datagram between the iPhone app and the Mac companion app.
///
/// Every datagram starts with a 4-byte header: magic `"MP"`, protocol version, message type.
/// Multi-byte fields are big-endian. Only the handshake travels in the clear; everything
/// else is a ``SessionMessage`` inside a `sealed` message (see ``SecureChannel``).
///
/// | Type | Message | Direction   | Payload                                                         |
/// |------|---------|-------------|-----------------------------------------------------------------|
/// | 1    | hello   | phone → Mac | identity key (32), ephemeral key (32), player name (UTF-8, rest) |
/// | 2    | pending | Mac → phone | none: waiting for the user to allow this phone on the Mac       |
/// | 3    | denied  | Mac → phone | none                                                            |
/// | 4    | full    | Mac → phone | none: every slot is taken                                       |
/// | 5    | welcome | Mac → phone | Mac ephemeral key (32), sealed ``SessionMessage/slot(_:)``      |
/// | 6    | sealed  | both        | ChaCha20-Poly1305 box: nonce (12), ciphertext, tag (16)         |
///
/// The phone repeats hello until it gets an answer. pending, denied and full aren't
/// authenticated, so a forged one can at most make a phone wait.
public enum Message: Equatable, Sendable {
    case hello(identity: Data, ephemeral: Data, name: String)
    case pending
    case denied
    case full
    case welcome(ephemeral: Data, sealed: Data)
    case sealed(Data)

    public static let magic: [UInt8] = Array("MP".utf8)
    public static let version: UInt8 = 2
    public static let keySize = 32
    public static let maxNameLength = 32

    private enum MessageType: UInt8 {
        case hello = 1, pending, denied, full, welcome, sealed
    }

    public func encoded() -> Data {
        var data = Data(Self.magic + [Self.version])
        switch self {
        case .hello(let identity, let ephemeral, let name):
            data.append(MessageType.hello.rawValue)
            data += identity + ephemeral
            data += Data(name.prefix(Self.maxNameLength).utf8)
        case .pending:
            data.append(MessageType.pending.rawValue)
        case .denied:
            data.append(MessageType.denied.rawValue)
        case .full:
            data.append(MessageType.full.rawValue)
        case .welcome(let ephemeral, let sealed):
            data.append(MessageType.welcome.rawValue)
            data += ephemeral + sealed
        case .sealed(let box):
            data.append(MessageType.sealed.rawValue)
            data += box
        }
        return data
    }

    public init(decoding data: Data) throws(ParseError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw .tooShort }
        guard Array(bytes[0..<2]) == Self.magic else { throw .badMagic }
        guard bytes[2] == Self.version else { throw .unsupportedVersion(bytes[2]) }
        guard let type = MessageType(rawValue: bytes[3]) else { throw .unknownMessageType(bytes[3]) }
        // Copies, so every Data below starts at index 0.
        let payload = Array(bytes[4...])
        let keySize = Self.keySize

        switch type {
        case .hello:
            guard payload.count >= 2 * keySize else { throw .wrongLength }
            let name = String(decoding: payload[(2 * keySize)...], as: UTF8.self)
            self = .hello(
                identity: Data(payload[..<keySize]),
                ephemeral: Data(payload[keySize..<(2 * keySize)]),
                name: String(name.prefix(Self.maxNameLength))
            )
        case .pending, .denied, .full:
            guard payload.isEmpty else { throw .wrongLength }
            self = switch type {
            case .pending: .pending
            case .denied: .denied
            default: .full
            }
        case .welcome:
            guard payload.count > keySize else { throw .wrongLength }
            self = .welcome(ephemeral: Data(payload[..<keySize]), sealed: Data(payload[keySize...]))
        case .sealed:
            guard !payload.isEmpty else { throw .wrongLength }
            self = .sealed(Data(payload))
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

/// A message inside an encrypted session. Its first byte is the type:
///
/// | Type | Message | Direction   | Payload                                                                   |
/// |------|---------|-------------|---------------------------------------------------------------------------|
/// | 1    | state   | phone → Mac | sequence u32, buttons u16, left x/y, right x/y (i16), triggers (u8 each)   |
/// | 2    | goodbye | phone → Mac | none: the user disconnected (FR-02)                                       |
/// | 3    | ping    | Mac → phone | token u64: measures latency and tells the phone the Mac is still there   |
/// | 4    | pong    | phone → Mac | the ping's token                                                          |
/// | 5    | slot    | Mac → phone | slot u8 (player number minus one), inside the welcome                     |
public enum SessionMessage: Equatable, Sendable {
    /// A complete controller snapshot. The phone sends snapshots rather than events,
    /// so a lost datagram is corrected by the next one and no button can get stuck.
    case state(sequence: UInt32, ControllerState)
    case goodbye
    case ping(token: UInt64)
    case pong(token: UInt64)
    case slot(UInt8)

    private enum MessageType: UInt8 {
        case state = 1, goodbye, ping, pong, slot
    }

    /// Whether `sequence` was sent after `other`, allowing for wrap-around. UDP can reorder
    /// datagrams, so the Mac drops states older than the last one it applied. This also
    /// makes replayed states useless.
    public static func isSequence(_ sequence: UInt32, newerThan other: UInt32) -> Bool {
        let distance = sequence &- other
        return distance != 0 && distance < UInt32(1) << 31
    }

    public func encoded() -> Data {
        var data = Data()
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
        case .goodbye:
            data.append(MessageType.goodbye.rawValue)
        case .ping(let token):
            data.append(MessageType.ping.rawValue)
            data.appendBigEndian(token)
        case .pong(let token):
            data.append(MessageType.pong.rawValue)
            data.appendBigEndian(token)
        case .slot(let slot):
            data.append(MessageType.slot.rawValue)
            data.append(slot)
        }
        return data
    }

    public init(decoding data: Data) throws(Message.ParseError) {
        let bytes = [UInt8](data)
        guard let first = bytes.first else { throw .tooShort }
        guard let type = MessageType(rawValue: first) else { throw .unknownMessageType(first) }

        var reader = BigEndianReader(bytes: bytes, offset: 1)
        func requireLength(_ payloadLength: Int) throws(Message.ParseError) {
            guard bytes.count == 1 + payloadLength else { throw .wrongLength }
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
        case .goodbye:
            try requireLength(0)
            self = .goodbye
        case .ping:
            try requireLength(8)
            self = .ping(token: reader.read(UInt64.self))
        case .pong:
            try requireLength(8)
            self = .pong(token: reader.read(UInt64.self))
        case .slot:
            try requireLength(1)
            self = .slot(bytes[1])
        }
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
