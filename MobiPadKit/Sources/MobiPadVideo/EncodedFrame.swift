import Foundation

/// One compressed H.264 video frame, as it travels from the Mac to the phone.
///
/// Wire format (big-endian):
///
/// | Field          | Size | Notes                                                        |
/// |----------------|------|--------------------------------------------------------------|
/// | flags          | 1    | bit 0: keyframe                                              |
/// | parameter sets | 1    | count, then per set: length u16 and the bytes (SPS, PPS)     |
/// | sample         | rest | the frame's NAL units, each prefixed with its length (AVCC)  |
///
/// Keyframes carry the parameter sets, so the phone can start decoding at any keyframe.
public struct EncodedFrame: Equatable, Sendable {
    public var isKeyframe: Bool
    /// The SPS and PPS. Empty on frames that aren't keyframes.
    public var parameterSets: [Data]
    /// Length-prefixed NAL units, as VideoToolbox writes and reads them.
    public var sample: Data

    public init(isKeyframe: Bool, parameterSets: [Data] = [], sample: Data) {
        self.isKeyframe = isKeyframe
        self.parameterSets = parameterSets
        self.sample = sample
    }

    public struct ParseError: Error, Equatable {}

    public func encoded() -> Data {
        var data = Data([isKeyframe ? 1 : 0, UInt8(parameterSets.count)])
        for set in parameterSets {
            data.append(UInt8(set.count >> 8))
            data.append(UInt8(set.count & 0xFF))
            data += set
        }
        data += sample
        return data
    }

    public init(decoding data: Data) throws(ParseError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw ParseError() }
        isKeyframe = bytes[0] & 1 != 0
        var offset = 2
        parameterSets = []
        for _ in 0..<bytes[1] {
            guard offset + 2 <= bytes.count else { throw ParseError() }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard length > 0, offset + length <= bytes.count else { throw ParseError() }
            parameterSets.append(Data(bytes[offset..<offset + length]))
            offset += length
        }
        guard offset < bytes.count else { throw ParseError() }
        sample = Data(bytes[offset...])
    }
}
