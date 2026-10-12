import Foundation

/// The stream probe's datagrams: a development tool that measures how long the picture takes from
/// the Mac to the phone, before the stream is built into the app. Not encrypted, so it runs on its
/// own port and Bonjour type, separate from the controller connection.
///
/// Every datagram starts with magic `"MV"` and a type byte:
///
/// | Type | Message   | Direction   | Payload                                                     |
/// |------|-----------|-------------|-------------------------------------------------------------|
/// | 1    | subscribe | phone → Mac | none: start or keep streaming to this phone (every second)  |
/// | 2    | fragment  | Mac → phone | a ``VideoFragment``                                         |
/// | 3    | keyframe  | phone → Mac | none: a frame was lost, send a keyframe                     |
/// | 4    | seen      | phone → Mac | marker white (u8, 0 or 1): the first frame showing a switch |
/// | 5    | stats     | phone → Mac | frames completed, lost, decoded (u32 each), decode µs (u32) |
public enum ProbeMessage: Equatable, Sendable {
    case subscribe
    case fragment(VideoFragment)
    case keyframe
    case seen(white: Bool)
    case stats(PhoneStats)

    public static let bonjourType = "_mobipad-video._udp"
    private static let magic = Array("MV".utf8)

    public struct PhoneStats: Equatable, Sendable {
        public var completed: UInt32
        public var lost: UInt32
        public var decoded: UInt32
        /// The mean time one decode took since the last report, in microseconds.
        public var meanDecodeMicroseconds: UInt32

        public init(completed: UInt32, lost: UInt32, decoded: UInt32, meanDecodeMicroseconds: UInt32) {
            self.completed = completed
            self.lost = lost
            self.decoded = decoded
            self.meanDecodeMicroseconds = meanDecodeMicroseconds
        }
    }

    public struct ParseError: Error, Equatable {}

    public func encoded() -> Data {
        var data = Data(Self.magic)
        switch self {
        case .subscribe:
            data.append(1)
        case .fragment(let fragment):
            data.append(2)
            data += fragment.encoded()
        case .keyframe:
            data.append(3)
        case .seen(let white):
            data.append(4)
            data.append(white ? 1 : 0)
        case .stats(let stats):
            data.append(5)
            for value in [stats.completed, stats.lost, stats.decoded, stats.meanDecodeMicroseconds] {
                withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    public init(decoding data: Data) throws(ParseError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, Array(bytes[0..<2]) == Self.magic else { throw ParseError() }
        let payload = Data(bytes[3...])
        switch bytes[2] {
        case 1 where payload.isEmpty:
            self = .subscribe
        case 2:
            do {
                self = .fragment(try VideoFragment(decoding: payload))
            } catch {
                throw ParseError()
            }
        case 3 where payload.isEmpty:
            self = .keyframe
        case 4 where payload.count == 1 && payload[0] <= 1:
            self = .seen(white: payload[0] == 1)
        case 5 where payload.count == 16:
            let values = stride(from: 0, to: 16, by: 4).map { offset in
                payload[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            }
            self = .stats(PhoneStats(completed: values[0], lost: values[1], decoded: values[2], meanDecodeMicroseconds: values[3]))
        default:
            throw ParseError()
        }
    }
}
