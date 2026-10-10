import CoreMedia
import Foundation
import Testing
@testable import MobiPadVideo

struct EncodedFrameTests {
    @Test func roundTripsAKeyframe() throws {
        let frame = EncodedFrame(isKeyframe: true, parameterSets: [Data([0x67, 1, 2]), Data([0x68, 3])], sample: Data([0, 0, 0, 1, 0x65]))
        #expect(frame.encoded() == Data([1, 2, 0, 3, 0x67, 1, 2, 0, 2, 0x68, 3, 0, 0, 0, 1, 0x65]))
        #expect(try EncodedFrame(decoding: frame.encoded()) == frame)
    }

    @Test func rejectsTruncatedFrames() {
        // Says it has a parameter set of 5 bytes but has only 2.
        #expect(throws: EncodedFrame.ParseError.self) { try EncodedFrame(decoding: Data([1, 1, 0, 5, 9, 9])) }
        // No sample after the parameter sets.
        #expect(throws: EncodedFrame.ParseError.self) { try EncodedFrame(decoding: Data([0, 0])) }
    }
}

struct VideoFragmentTests {
    @Test func splitsAndRoundTrips() throws {
        let data = Data((0..<2_500).map { UInt8($0 % 251) })
        let fragments = try #require(VideoFragment.split(data, frame: 7))
        #expect(fragments.map(\.payload.count) == [1_150, 1_150, 200])
        #expect(fragments.allSatisfy { $0.count == 3 && $0.frame == 7 })
        for fragment in fragments {
            #expect(try VideoFragment(decoding: fragment.encoded()) == fragment)
        }
        #expect(fragments.reduce(Data()) { $0 + $1.payload } == data)
    }

    @Test func refusesFramesThatAreTooLarge() {
        let data = Data(count: VideoFragment.maxPayload * Int(VideoFragment.maxCount) + 1)
        #expect(VideoFragment.split(data, frame: 0) == nil)
    }

    @Test func rejectsAnIndexPastTheCount() {
        let bad = VideoFragment(frame: 1, index: 3, count: 3, payload: Data([1])).encoded()
        #expect(throws: VideoFragment.ParseError.self) { try VideoFragment(decoding: bad) }
    }
}

struct VideoReceiverTests {
    private func fragments(_ frame: EncodedFrame, number: UInt32) -> [VideoFragment] {
        VideoFragment.split(frame.encoded(), frame: number, maxPayload: 4)!
    }

    private let keyframe = EncodedFrame(isKeyframe: true, parameterSets: [Data([0x67])], sample: Data([1, 2, 3, 4, 5, 6]))
    private let delta = EncodedFrame(isKeyframe: false, sample: Data([7, 8, 9, 10, 11]))

    /// Feeds fragments and returns the frames that came out.
    private func feed(_ receiver: inout VideoReceiver, _ fragments: [VideoFragment]) -> [EncodedFrame] {
        fragments.compactMap { receiver.receive($0).frame }
    }

    @Test func deliversFramesInOrder() {
        var receiver = VideoReceiver()
        let out = feed(&receiver, fragments(keyframe, number: 1) + fragments(delta, number: 2))
        #expect(out == [keyframe, delta])
        #expect(receiver.lostFrames == 0)
    }

    @Test func putsReorderedFragmentsTogether() {
        var receiver = VideoReceiver()
        let out = feed(&receiver, fragments(keyframe, number: 1).reversed())
        #expect(out == [keyframe])
    }

    @Test func waitsForTheFirstKeyframe() {
        var receiver = VideoReceiver()
        let pieces = fragments(delta, number: 1)
        let outputs = pieces.map { receiver.receive($0) }
        #expect(outputs.allSatisfy { $0.frame == nil && $0.wantsKeyframe })
    }

    @Test func afterALostFrameSkipsToTheNextKeyframe() {
        var receiver = VideoReceiver()
        #expect(feed(&receiver, fragments(keyframe, number: 1)) == [keyframe])

        // Frame 2 loses its last fragment.
        _ = feed(&receiver, Array(fragments(delta, number: 2).dropLast()))
        let afterLoss = fragments(delta, number: 3).map { receiver.receive($0) }
        #expect(afterLoss.last == .init(frame: nil, wantsKeyframe: true))
        #expect(receiver.lostFrames == 1)

        // A late fragment of the lost frame changes nothing.
        #expect(receiver.receive(fragments(delta, number: 2).last!) == .init(frame: nil, wantsKeyframe: true))

        let recovered = fragments(keyframe, number: 4).map { receiver.receive($0) }
        #expect(recovered.last == .init(frame: keyframe, wantsKeyframe: false))
        #expect(feed(&receiver, fragments(delta, number: 5)) == [delta])
    }

    @Test func ignoresDuplicateFragments() {
        var receiver = VideoReceiver()
        let pieces = fragments(keyframe, number: 1)
        let out = feed(&receiver, [pieces[0], pieces[0]] + pieces.dropFirst())
        #expect(out == [keyframe])
    }

    @Test func keepsFewPartialFramesUnderHeavyLoss() {
        var receiver = VideoReceiver()
        _ = feed(&receiver, fragments(keyframe, number: 1))
        // A hundred frames that each lose their last fragment.
        for number in UInt32(2)...101 {
            _ = feed(&receiver, Array(fragments(delta, number: number).dropLast()))
        }
        // The oldest partial frames were forgotten, so their last fragments complete nothing.
        #expect(receiver.receive(fragments(delta, number: 2).last!).frame == nil)
        #expect(receiver.completedFrames == 1)
        // The newest still completes, but follows a gap, so it waits for a keyframe.
        #expect(receiver.receive(fragments(delta, number: 101).last!) == .init(frame: nil, wantsKeyframe: true))
        #expect(receiver.completedFrames == 2)
    }

    @Test func frameNumbersWrapAround() {
        var receiver = VideoReceiver()
        let out = feed(&receiver, fragments(keyframe, number: .max) + fragments(delta, number: 0))
        #expect(out == [keyframe, delta])
    }
}

struct ProbeMessageTests {
    @Test func roundTrips() throws {
        let messages: [ProbeMessage] = [
            .subscribe,
            .fragment(VideoFragment(frame: 3, index: 1, count: 2, payload: Data([9, 9]))),
            .keyframe,
            .seen(white: true),
            .seen(white: false),
            .stats(.init(completed: 1, lost: 2, decoded: 3, meanDecodeMicroseconds: 4_000)),
        ]
        for message in messages {
            #expect(try ProbeMessage(decoding: message.encoded()) == message)
        }
    }

    @Test func rejectsOtherDatagrams() {
        // A controller message ("MP").
        #expect(throws: ProbeMessage.ParseError.self) { try ProbeMessage(decoding: Data("MP\u{3}\u{1}".utf8)) }
        #expect(throws: ProbeMessage.ParseError.self) { try ProbeMessage(decoding: Data("MV\u{4}\u{2}".utf8)) }
    }
}

/// The real hardware encoder and decoder on this Mac.
@Suite(.timeLimit(.minutes(1)))
struct CodecTests {
    private final class Collected: @unchecked Sendable {
        let lock = NSLock()
        var frames: [EncodedFrame] = []
        var errors: [VideoEncoder.EncoderError] = []
    }

    /// Encodes the test pattern with the marker switching, and returns the compressed frames.
    private func encode(markers: [Bool], keyframeAt: Set<Int> = []) async throws -> [EncodedFrame] {
        let collected = Collected()
        let encoder = try VideoEncoder { result in
            collected.lock.withLock {
                switch result {
                case .success(let frame): collected.frames.append(frame)
                case .failure(let error): collected.errors.append(error)
                }
            }
        }
        let pattern = try TestPattern()
        for (number, white) in markers.enumerated() {
            let picture = try pattern.frame(number, markerWhite: white)
            try encoder.encode(picture, time: CMTime(value: CMTimeValue(number), timescale: 60), forceKeyframe: keyframeAt.contains(number))
        }
        // Real time with no reordering: frames come out one by one, but asynchronously.
        for _ in 0..<200 where collected.lock.withLock({ collected.frames.count + collected.errors.count }) < markers.count {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try collected.lock.withLock {
            try #require(collected.errors.isEmpty, "\(collected.errors)")
            return collected.frames
        }
    }

    @Test func markerSurvivesEncodingAndDecoding() async throws {
        let markers = (0..<30).map { $0 / 5 % 2 == 1 }
        let frames = try await encode(markers: markers)
        #expect(frames.count == markers.count)
        #expect(frames.first?.isKeyframe == true)
        #expect(frames.first?.parameterSets.count == 2)

        let decoder = VideoDecoder()
        var seen: [Bool] = []
        for frame in frames {
            // Through the wire format and the receiver's datagrams, as on the phone.
            let decoded = try EncodedFrame(decoding: frame.encoded())
            let picture = try decoder.decode(decoded)
            #expect(CVPixelBufferGetWidth(picture) == 854)
            seen.append(LatencyMarker.isWhite(picture))
        }
        #expect(seen == markers)
    }

    @Test func forcedKeyframesCarryParameterSets() async throws {
        let frames = try await encode(markers: Array(repeating: false, count: 10), keyframeAt: [6])
        #expect(frames.enumerated().filter(\.element.isKeyframe).map(\.offset) == [0, 6])
        #expect(frames[6].parameterSets == frames[0].parameterSets)
        #expect(frames[3].parameterSets.isEmpty)
    }

    @Test func decoderNeedsAKeyframeFirst() async throws {
        let frames = try await encode(markers: [false, false])
        #expect(throws: VideoDecoder.DecoderError.noFormatYet) { try VideoDecoder().decode(frames[1]) }
    }
}
