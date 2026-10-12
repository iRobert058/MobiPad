import CoreMedia
import Foundation
import VideoToolbox

/// Decompresses the H.264 frames from ``VideoEncoder`` with the hardware decoder, one at a time:
/// ``decode(_:)`` returns the picture, so a frame is never held back waiting for the next one.
///
/// Not thread-safe: call it from one queue.
public final class VideoDecoder {
    public enum DecoderError: Error, Equatable {
        /// A frame that isn't a keyframe arrived before any keyframe.
        case noFormatYet
        case badParameterSets(OSStatus)
        case couldNotCreate(OSStatus)
        case couldNotDecode(OSStatus)
    }

    private var format: CMVideoFormatDescription?
    private var parameterSets: [Data] = []
    private var session: VTDecompressionSession?

    public init() {}

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    /// The decoded picture in NV12 (`420v`), which ``LatencyMarker`` reads and the display layer shows.
    public func decode(_ frame: EncodedFrame) throws(DecoderError) -> CVPixelBuffer {
        if frame.isKeyframe, frame.parameterSets != parameterSets {
            try makeSession(parameterSets: frame.parameterSets)
        }
        guard let session, let format else { throw .noFormatYet }

        let sampleBuffer = try makeSampleBuffer(frame.sample, format: format)
        let result = DecodeResult()
        // Without the asynchronous flag, VideoToolbox calls the handler before it returns.
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sampleBuffer, flags: [], infoFlagsOut: nil
        ) { status, _, imageBuffer, _, _ in
            result.value = if status == noErr, let imageBuffer { .success(imageBuffer) } else { .failure(.couldNotDecode(status)) }
        }
        guard status == noErr, case .success(let picture)? = result.value else {
            // Also after the system invalidated the session, as iOS does in the background: start over
            // at the next keyframe, even if its parameter sets are the same.
            reset()
            if status == noErr, case .failure(let error)? = result.value { throw error }
            throw .couldNotDecode(status)
        }
        return picture
    }

    private func reset() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        format = nil
        parameterSets = []
    }

    private func makeSession(parameterSets: [Data]) throws(DecoderError) {
        var newFormat: CMVideoFormatDescription?
        let status = parameterSets.withPointers { pointers, sizes in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &newFormat
            )
        }
        guard status == noErr, let newFormat else { throw .badParameterSets(status) }

        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary
        var newSession: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: newFormat,
            decoderSpecification: nil,
            imageBufferAttributes: attributes,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        guard createStatus == noErr, let newSession else { throw .couldNotCreate(createStatus) }
        let realTimeStatus = VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        guard realTimeStatus == noErr else { throw .couldNotCreate(realTimeStatus) }
        session = newSession
        format = newFormat
        self.parameterSets = parameterSets
    }

    private func makeSampleBuffer(_ sample: Data, format: CMVideoFormatDescription) throws(DecoderError) -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: sample.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: sample.count, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else { throw .couldNotDecode(status) }
        status = sample.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: sample.count)
        }
        guard status == noErr else { throw .couldNotDecode(status) }

        var sampleBuffer: CMSampleBuffer?
        var size = sample.count
        status = CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: blockBuffer, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { throw .couldNotDecode(status) }
        return sampleBuffer
    }
}

/// Carries the decoded picture out of VideoToolbox's handler, which runs before the decode call returns.
private final class DecodeResult: @unchecked Sendable {
    var value: Result<CVPixelBuffer, VideoDecoder.DecoderError>?
}

private extension Array where Element == Data {
    /// Calls `body` with pointers to every element's bytes, valid only inside it.
    func withPointers<R>(_ body: ([UnsafePointer<UInt8>], [Int]) -> R) -> R {
        func nest(_ index: Int, _ pointers: [UnsafePointer<UInt8>]) -> R {
            guard index < count else { return body(pointers, map(\.count)) }
            return self[index].withUnsafeBytes { bytes in
                nest(index + 1, pointers + [bytes.bindMemory(to: UInt8.self).baseAddress!])
            }
        }
        return nest(0, [])
    }
}
