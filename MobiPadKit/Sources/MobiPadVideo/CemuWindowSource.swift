#if os(macOS)
import CoreGraphics
import CoreMedia
import Foundation
import MobiPadProtocol
import os
import ScreenCaptureKit

/// Captures Cemu's GamePad window, and nothing else on the screen, with ScreenCaptureKit.
///
/// Cemu shows the GamePad in a window of its own when Options → Separate GamePad view is on. The window
/// is captured even while other windows cover it. Needs the Screen Recording permission.
public final class CemuWindowSource: NSObject, FrameSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public static let bundleIdentifier = "info.cemu.Cemu"
    /// `PadViewFrame`'s title, followed by " - FPS: …" while a game runs (`wxWindowSystem.cpp`).
    static let titlePrefix = "GamePad View"
    /// The window's title bar, cut off the top. WORKAROUND: macOS doesn't tell another app's title bar
    /// height; 28 points is a standard window's on macOS 14 and later (*assumed* for Cemu's wxWidgets window).
    static let titleBarHeight: CGFloat = 28

    private let log = Logger(subsystem: "MobiPad", category: "capture")
    private let queue = DispatchQueue(label: "MobiPad.CemuWindowSource", qos: .userInteractive)
    private let lock = NSLock()
    private let size: (width: Int, height: Int)
    private let framesPerSecond: Int
    private var stream: SCStream?
    private var onFrame: (@Sendable (CVPixelBuffer) -> Void)?
    private var onStop: (@Sendable () -> Void)?

    public init(width: Int = 854, height: Int = 480, framesPerSecond: Int = 60) {
        size = (width, height)
        self.framesPerSecond = framesPerSecond
    }

    /// Whether a window is Cemu's GamePad view.
    static func isGamePadWindow(bundleIdentifier: String?, title: String?) -> Bool {
        bundleIdentifier == Self.bundleIdentifier && title?.hasPrefix(Self.titlePrefix) == true
    }

    /// The part of a window of `size` points that shows the GamePad's picture: below the title bar, the
    /// largest 16:9 area in the middle, as Cemu keeps the picture's shape and fills the rest with black.
    static func pictureRect(inWindowOfSize size: CGSize) -> CGRect {
        let content = CGRect(x: 0, y: titleBarHeight, width: size.width, height: max(size.height - titleBarHeight, 1))
        let aspect: CGFloat = 16 / 9
        let width = min(content.width, content.height * aspect)
        let height = width / aspect
        return CGRect(x: content.midX - width / 2, y: content.midY - height / 2, width: width, height: height)
    }

    public func start(
        onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) async -> SessionMessage.VideoStatus {
        // Asking for the windows without permission would show macOS's prompt; the Mac's menu does that.
        guard CGPreflightScreenCaptureAccess() else { return .noPermission }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            log.error("Couldn't list the windows: \(error.localizedDescription, privacy: .public)")
            return .noPermission
        }
        guard let window = content.windows.first(where: {
            Self.isGamePadWindow(bundleIdentifier: $0.owningApplication?.bundleIdentifier, title: $0.title)
        }) else {
            return .noWindow
        }

        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.sourceRect = Self.pictureRect(inWindowOfSize: window.frame.size)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = false
        configuration.queueDepth = 5
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            lock.withLock {
                self.onFrame = onFrame
                self.onStop = onStop
                self.stream = stream
            }
            try await stream.startCapture()
        } catch {
            log.error("Couldn't capture the GamePad window: \(error.localizedDescription, privacy: .public)")
            lock.withLock {
                self.stream = nil
                self.onFrame = nil
                self.onStop = nil
            }
            return .noWindow
        }
        log.notice("Capturing Cemu's GamePad window")
        return .streaming
    }

    public func stop() async {
        let stream = lock.withLock {
            defer {
                self.stream = nil
                onFrame = nil
                onStop = nil
            }
            return self.stream
        }
        guard let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            // Already stopped, such as when the window closed.
            log.debug("Stopping the capture: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let rawStatus = info[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let picture = sampleBuffer.imageBuffer
        else { return }
        let onFrame = lock.withLock { self.stream === stream ? self.onFrame : nil }
        onFrame?(picture)
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        log.notice("The GamePad window's capture stopped: \(error.localizedDescription, privacy: .public)")
        let onStop = lock.withLock {
            guard self.stream === stream else { return nil as (@Sendable () -> Void)? }
            defer {
                self.stream = nil
                self.onFrame = nil
                self.onStop = nil
            }
            return self.onStop
        }
        onStop?()
    }
}
#endif
