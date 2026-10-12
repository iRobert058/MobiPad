#if os(macOS)
import CoreMedia
import Foundation
import VideoToolbox

/// Compresses frames to H.264 with the Mac's hardware encoder, tuned for low latency: no reordered
/// frames, so each frame leaves the encoder as soon as it's done, and Apple's low-latency rate control.
public final class VideoEncoder: @unchecked Sendable {
    public struct Settings: Sendable {
        public var width: Int32 = 854
        public var height: Int32 = 480
        public var framesPerSecond: Double = 60
        public var bitsPerSecond: Int = 6_000_000
        /// A keyframe at least this often, so a phone that joins late or loses one still gets a picture.
        public var keyframeIntervalSeconds: Double = 2

        public init() {}
    }

    public enum EncoderError: Error {
        case couldNotCreate(OSStatus)
        case couldNotEncode(OSStatus)
        case unreadableOutput
    }

    /// Called on VideoToolbox's thread with each compressed frame, or the error for a frame that failed,
    /// along with the time passed to ``encode(_:time:forceKeyframe:)``. The encoder may also drop a frame
    /// on its own to keep the bit rate; then there's no call.
    public typealias Output = @Sendable (_ time: CMTime, _ result: Result<EncodedFrame, EncoderError>) -> Void

    public let settings: Settings
    private let session: VTCompressionSession
    private let output: Output

    public init(settings: Settings = Settings(), output: @escaping Output) throws(EncoderError) {
        self.settings = settings
        self.output = output
        var session: VTCompressionSession?
        let specification = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: settings.width,
            height: settings.height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { throw .couldNotCreate(status) }
        self.session = session

        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate: settings.bitsPerSecond,
            kVTCompressionPropertyKey_ExpectedFrameRate: settings.framesPerSecond,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: settings.keyframeIntervalSeconds,
        ]
        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
            guard status == noErr else { throw .couldNotCreate(status) }
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        VTCompressionSessionInvalidate(session)
    }

    /// Changes the bit rate while encoding; the next frames use it.
    public func setBitsPerSecond(_ bitsPerSecond: Int) throws(EncoderError) {
        let status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitsPerSecond as CFNumber)
        guard status == noErr else { throw .couldNotCreate(status) }
    }

    /// Compresses one frame. `time` only needs to increase from frame to frame.
    public func encode(_ pixelBuffer: CVPixelBuffer, time: CMTime, forceKeyframe: Bool = false) throws(EncoderError) {
        let options = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let output = output
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: time,
            duration: .invalid,
            frameProperties: options,
            infoFlagsOut: nil
        ) { status, infoFlags, sampleBuffer in
            if status != noErr {
                output(time, .failure(.couldNotEncode(status)))
            } else if infoFlags.contains(.frameDropped) || sampleBuffer == nil {
                return
            } else if let frame = EncodedFrame(sampleBuffer!) {
                output(time, .success(frame))
            } else {
                output(time, .failure(.unreadableOutput))
            }
        }
        guard status == noErr else { throw .couldNotEncode(status) }
    }
}

extension EncodedFrame {
    /// Takes the compressed data out of VideoToolbox's output. Nil for a dropped frame.
    init?(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = sampleBuffer.dataBuffer, let format = sampleBuffer.formatDescription else { return nil }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        var parameterSets: [Data] = []
        if !notSync {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil
            )
            for index in 0..<count {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
                )
                guard let pointer else { return nil }
                parameterSets.append(Data(bytes: pointer, count: size))
            }
        }
        guard let sample = try? blockBuffer.dataBytes() else { return nil }
        self.init(isKeyframe: !notSync, parameterSets: parameterSets, sample: sample)
    }
}
#endif
