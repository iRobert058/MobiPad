import CoreVideo
import Foundation
import os

/// The phone's side of the GamePad screen: puts the video's datagrams back together, decodes the
/// frames on a queue of its own, and asks for a keyframe when one was lost.
public final class VideoPlayer: @unchecked Sendable {
    /// Counters since the last ``takeStats()``.
    public struct Stats: Sendable, Equatable {
        public var completed = 0
        public var lost = 0
        public var decoded = 0
        /// The mean time a decode took, in microseconds.
        public var meanDecodeMicroseconds = 0

        public init() {}
    }

    private let log = Logger(subsystem: "MobiPad", category: "video")
    private let queue = DispatchQueue(label: "MobiPad.VideoPlayer", qos: .userInteractive)
    private var receiver = VideoReceiver()
    private let decoder = VideoDecoder()
    private var lastKeyframeRequest = ContinuousClock.now - .seconds(1)
    private var stats = Stats()
    private var decodeMicroseconds = 0
    private let onPicture: @Sendable (CVPixelBuffer) -> Void
    private let requestKeyframe: @Sendable () -> Void

    /// - Parameters:
    ///   - onPicture: each decoded picture, on the player's queue.
    ///   - requestKeyframe: asks the Mac for a keyframe, at most ten times a second.
    public init(onPicture: @escaping @Sendable (CVPixelBuffer) -> Void, requestKeyframe: @escaping @Sendable () -> Void) {
        self.onPicture = onPicture
        self.requestKeyframe = requestKeyframe
    }

    /// Takes one datagram's worth of video, a ``VideoFragment``, from any thread.
    public func receive(_ data: Data) {
        queue.async { [self] in handle(data) }
    }

    /// Returns the counters and starts new ones.
    public func takeStats() -> Stats {
        queue.sync {
            var result = stats
            result.completed = receiver.completedFrames
            result.lost = receiver.lostFrames
            result.meanDecodeMicroseconds = stats.decoded == 0 ? 0 : decodeMicroseconds / stats.decoded
            stats = Stats()
            decodeMicroseconds = 0
            return result
        }
    }

    // MARK: - On queue

    private func handle(_ data: Data) {
        let fragment: VideoFragment
        do {
            fragment = try VideoFragment(decoding: data)
        } catch {
            log.error("Dropped a malformed video datagram")
            return
        }
        let output = receiver.receive(fragment)
        if output.wantsKeyframe {
            askForKeyframe()
        }
        guard let frame = output.frame else { return }

        let start = ContinuousClock.now
        let picture: CVPixelBuffer
        do {
            picture = try decoder.decode(frame)
        } catch {
            log.error("Couldn't decode a video frame: \(String(describing: error), privacy: .public)")
            receiver.requireKeyframe()
            askForKeyframe()
            return
        }
        let elapsed = ContinuousClock.now - start
        decodeMicroseconds += Int(elapsed.components.seconds) * 1_000_000 + Int(elapsed.components.attoseconds / 1_000_000_000_000)
        stats.decoded += 1
        onPicture(picture)
    }

    private func askForKeyframe() {
        guard ContinuousClock.now - lastKeyframeRequest > .milliseconds(100) else { return }
        lastKeyframeRequest = .now
        requestKeyframe()
    }
}
