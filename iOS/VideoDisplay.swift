import AVFoundation
import CoreMedia
import os
import SwiftUI

/// Shows decoded pictures as they arrive, without waiting for presentation times: for live video, the
/// newest picture is the right one.
final class VideoDisplay: Sendable {
    /// Only touched on the main thread, by SwiftUI.
    nonisolated(unsafe) let layer = AVSampleBufferDisplayLayer()
    /// Takes sample buffers from any thread (AVQueuedSampleBufferRendering), but isn't marked Sendable.
    nonisolated(unsafe) private let renderer: AVSampleBufferVideoRenderer
    private let log = Logger(subsystem: "MobiPad", category: "video")

    @MainActor init() {
        layer.videoGravity = .resizeAspect
        renderer = layer.sampleBufferRenderer
    }

    /// From any thread.
    func show(_ picture: CVPixelBuffer) {
        guard let sample = Self.sampleBuffer(for: picture) else {
            log.error("Couldn't wrap a decoded picture for display")
            return
        }
        renderer.enqueue(sample)
    }

    /// Clears the picture, from any thread.
    func clear() {
        renderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    private static func sampleBuffer(for picture: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: picture, formatDescriptionOut: &format) == noErr,
              let format
        else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: picture, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sample
    }
}

/// A view that hosts a ``VideoDisplay``'s layer, filling the view.
struct VideoDisplayView: UIViewRepresentable {
    let display: VideoDisplay

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(display.layer)
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}

    final class LayerView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
