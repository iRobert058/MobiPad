import Foundation

/// A piece of an encoded frame small enough for one UDP datagram.
///
/// Wire format (big-endian): frame number u32, index u16, count u16, then the payload.
public struct VideoFragment: Equatable, Sendable {
    /// Counts up by one per frame the Mac sends, wrapping around.
    public var frame: UInt32
    public var index: UInt16
    public var count: UInt16
    public var payload: Data

    public static let headerLength = 8
    /// Keeps a datagram, with the headers of the layers around it, under the usual 1,500-byte
    /// Ethernet MTU, so the network never has to split it.
    public static let maxPayload = 1_150
    /// A frame larger than this is dropped rather than sent: about 1.2 MB, far above a keyframe at the
    /// GamePad's size.
    public static let maxCount: UInt16 = 1_024

    public init(frame: UInt32, index: UInt16, count: UInt16, payload: Data) {
        self.frame = frame
        self.index = index
        self.count = count
        self.payload = payload
    }

    /// Splits a frame into fragments, or returns nil when it needs more than ``maxCount``.
    public static func split(_ data: Data, frame: UInt32, maxPayload: Int = maxPayload) -> [VideoFragment]? {
        let count = max(1, (data.count + maxPayload - 1) / maxPayload)
        guard count <= maxCount else { return nil }
        return (0..<count).map { index in
            let start = data.startIndex + index * maxPayload
            let end = min(start + maxPayload, data.endIndex)
            return VideoFragment(frame: frame, index: UInt16(index), count: UInt16(count), payload: Data(data[start..<end]))
        }
    }

    public struct ParseError: Error, Equatable {}

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerLength + payload.count)
        withUnsafeBytes(of: frame.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: index.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: count.bigEndian) { data.append(contentsOf: $0) }
        data += payload
        return data
    }

    public init(decoding data: Data) throws(ParseError) {
        let bytes = [UInt8](data)
        guard bytes.count > Self.headerLength else { throw ParseError() }
        frame = bytes[0..<4].reduce(0) { $0 << 8 | UInt32($1) }
        index = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        count = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        guard count > 0, count <= Self.maxCount, index < count else { throw ParseError() }
        payload = Data(bytes[Self.headerLength...])
    }
}

/// Puts frames back together on the phone and decides which ones can be decoded.
///
/// A frame that isn't a keyframe only decodes on top of the frame before it. So after a lost
/// fragment, the receiver skips frames until the next keyframe and asks the Mac for one, instead of
/// showing a broken picture.
public struct VideoReceiver: Sendable {
    public struct Output: Equatable, Sendable {
        /// A frame ready for the decoder, if this fragment completed one that can be decoded.
        public var frame: EncodedFrame?
        /// True when the Mac should send a keyframe: a frame was lost and none has arrived since.
        public var wantsKeyframe: Bool
    }

    /// Frames still missing fragments. Few at a time: they arrive almost in order on a local network.
    private var partial: [UInt32: Partial] = [:]
    static let maxPartialFrames = 8
    private var lastCompleted: UInt32?
    private var needsKeyframe = true
    /// Counters for the statistics.
    public private(set) var completedFrames = 0
    public private(set) var lostFrames = 0

    private struct Partial {
        var pieces: [Data?]
        var received = 0
    }

    public init() {}

    public mutating func receive(_ fragment: VideoFragment) -> Output {
        if let lastCompleted, !Self.isFrame(fragment.frame, newerThan: lastCompleted) {
            return Output(frame: nil, wantsKeyframe: needsKeyframe)
        }
        var frame = partial[fragment.frame] ?? Partial(pieces: Array(repeating: nil, count: Int(fragment.count)))
        // A fragment that doesn't match the others of its frame is forged or corrupt; drop it.
        guard frame.pieces.count == Int(fragment.count), frame.pieces[Int(fragment.index)] == nil else {
            return Output(frame: nil, wantsKeyframe: needsKeyframe)
        }
        frame.pieces[Int(fragment.index)] = fragment.payload
        frame.received += 1
        guard frame.received == frame.pieces.count else {
            partial[fragment.frame] = frame
            // Under heavy loss no frame completes; keep only the newest few.
            while partial.count > Self.maxPartialFrames, let oldest = partial.keys.min(by: { Self.isFrame($1, newerThan: $0) }) {
                partial[oldest] = nil
            }
            return Output(frame: nil, wantsKeyframe: needsKeyframe)
        }

        // Complete. Frames between the last one and this one are lost, including half-received ones.
        partial = partial.filter { Self.isFrame($0.key, newerThan: fragment.frame) }
        if let lastCompleted {
            let skipped = Int(fragment.frame &- lastCompleted) - 1
            if skipped > 0 {
                lostFrames += skipped
                needsKeyframe = true
            }
        }
        lastCompleted = fragment.frame
        completedFrames += 1

        let data = frame.pieces.reduce(into: Data()) { $0 += $1! }
        guard let encoded = try? EncodedFrame(decoding: data) else {
            lostFrames += 1
            needsKeyframe = true
            return Output(frame: nil, wantsKeyframe: true)
        }
        if encoded.isKeyframe {
            needsKeyframe = false
        }
        return Output(frame: needsKeyframe ? nil : encoded, wantsKeyframe: needsKeyframe)
    }

    /// Skips frames until the next keyframe, for when one couldn't be decoded.
    public mutating func requireKeyframe() {
        needsKeyframe = true
    }

    /// Wrap-around comparison of frame numbers, as for the controller's sequence numbers.
    static func isFrame(_ frame: UInt32, newerThan other: UInt32) -> Bool {
        let distance = frame &- other
        return distance != 0 && distance < UInt32(1) << 31
    }
}
