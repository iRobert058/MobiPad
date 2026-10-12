#if os(macOS)
import CoreMedia
import CoreVideo
import Foundation
import MobiPadProtocol
import os

/// Where the pictures come from: Cemu's GamePad window, or a test pattern in tests.
public protocol FrameSource: AnyObject, Sendable {
    /// Starts delivering pictures and returns `.streaming`, or returns why it can't. `onStop` is called
    /// once if it stops on its own, such as when the window closes.
    func start(
        onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) async -> SessionMessage.VideoStatus

    func stop() async
}

/// The Mac's side of the GamePad screen: captures pictures while a phone asks for them and the player
/// has turned the stream on, compresses them, and hands the datagrams to the players that asked.
///
/// Phones ask once a second while they show the GamePad screen (``request(slot:keyframe:)``), and each
/// answer tells them whether there's a picture, or what's missing. Capture stops a few seconds after the
/// last phone stops asking, so nothing is recorded while nobody looks.
public final class GamePadStreamer: @unchecked Sendable {
    public struct Timing: Sendable {
        /// A phone that hasn't asked for this long no longer gets the stream.
        public var requestTimeout: Duration = .seconds(3)
        /// How long to wait before trying the source again after it couldn't start.
        public var retryInterval: Duration = .seconds(2)
        /// Without a new picture for this long (a still screen), the last one is sent again, so a phone
        /// that lost a frame notices and can ask for a keyframe.
        public var refreshInterval: Duration = .seconds(1)
        public var tickInterval: Duration = .milliseconds(250)

        public init() {}
    }

    /// Sends a ``VideoFragment``'s bytes to the players in the set.
    public typealias Send = @Sendable (_ fragment: Data, _ slots: Set<Int>) -> Void
    public typealias SendStatus = @Sendable (_ status: SessionMessage.VideoStatus, _ slot: Int) -> Void

    private let log = Logger(subsystem: "MobiPad", category: "stream")
    private let queue = DispatchQueue(label: "MobiPad.GamePadStreamer", qos: .userInteractive)
    private let source: any FrameSource
    private let timing: Timing
    private var settings: VideoEncoder.Settings
    private let send: Send
    private let sendStatus: SendStatus
    private var timer: DispatchSourceTimer?

    private var isEnabled = false
    private var requesters: [Int: ContinuousClock.Instant] = [:]
    private enum Capture {
        case stopped(since: ContinuousClock.Instant)
        case starting
        case running
        /// Couldn't start; tried at the given time.
        case failed(SessionMessage.VideoStatus, at: ContinuousClock.Instant)
    }
    private var capture = Capture.stopped(since: .now - .seconds(60))
    /// Changes whenever capture starts or stops, so a late picture or stop from an old start is ignored.
    private var generation = 0
    private var encoder: VideoEncoder?
    private var frameNumber: UInt32 = 0
    private var inputNumber: Int64 = 0
    private var wantsKeyframe = true
    private var lastPicture: CVPixelBuffer?
    private var lastSubmitted = ContinuousClock.now

    public init(
        source: any FrameSource,
        settings: VideoEncoder.Settings = .init(),
        timing: Timing = .init(),
        send: @escaping Send,
        sendStatus: @escaping SendStatus
    ) {
        self.source = source
        self.settings = settings
        self.timing = timing
        self.send = send
        self.sendStatus = sendStatus
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: timing.tickInterval.seconds)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    deinit {
        timer?.cancel()
    }

    /// The player's switch in the Mac's menu. Off, nothing is captured, and phones are told so.
    public func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            isEnabled = enabled
            tick()
        }
    }

    /// The picture's quality: more bits a second is sharper, but more for the Wi-Fi to carry.
    public func setBitsPerSecond(_ bitsPerSecond: Int) {
        queue.async { [self] in
            settings.bitsPerSecond = bitsPerSecond
            do {
                try encoder?.setBitsPerSecond(bitsPerSecond)
            } catch {
                log.error("Couldn't change the bit rate: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A phone in `slot` asks for the stream, or for a keyframe after a lost frame.
    public func request(slot: Int, keyframe: Bool) {
        queue.async { [self] in
            let isNew = requesters[slot] == nil
            requesters[slot] = .now
            if keyframe || isNew {
                wantsKeyframe = true
                // A still screen sends no new pictures, so send the last one again as the keyframe.
                if case .running = capture, let lastPicture {
                    encode(lastPicture)
                }
            }
            sendStatus(currentStatus(), slot)
            tick()
        }
    }

    // MARK: - On queue

    private func currentStatus() -> SessionMessage.VideoStatus {
        guard isEnabled else { return .off }
        switch capture {
        case .running: return .streaming
        case .failed(let status, _): return status
        // Not known yet; the phone keeps its placeholder until the next answer.
        case .stopped, .starting: return .streaming
        }
    }

    private func tick() {
        let now = ContinuousClock.now
        requesters = requesters.filter { now - $0.value < timing.requestTimeout }
        let wanted = isEnabled && !requesters.isEmpty

        switch capture {
        case .running where !wanted:
            stopCapture()
        case .failed(_, let at) where !wanted:
            capture = .stopped(since: at)
        case .stopped where wanted:
            startCapture()
        case .failed(_, let at) where now - at >= timing.retryInterval:
            startCapture()
        case .running:
            if let lastPicture, now - lastSubmitted >= timing.refreshInterval {
                encode(lastPicture)
            }
        default:
            break
        }
    }

    private func startCapture() {
        capture = .starting
        generation += 1
        let generation = generation
        let source = source
        let onFrame: @Sendable (CVPixelBuffer) -> Void = { [weak self] picture in
            guard let self else { return }
            let picture = UncheckedPicture(picture)
            queue.async { self.received(picture.value, generation: generation) }
        }
        let onStop: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            queue.async { self.stopped(generation: generation) }
        }
        Task { [weak self] in
            let status = await source.start(onFrame: onFrame, onStop: onStop)
            guard let self else { return }
            queue.async { self.started(status, generation: generation) }
        }
    }

    private func started(_ status: SessionMessage.VideoStatus, generation: Int) {
        guard generation == self.generation, case .starting = capture else {
            // Stopped or restarted while it was starting.
            if status == .streaming, generation == self.generation { stopCapture() }
            return
        }
        if status == .streaming {
            do {
                encoder = try makeEncoder()
            } catch {
                log.error("Couldn't create the video encoder: \(String(describing: error), privacy: .public)")
                capture = .failed(.noWindow, at: .now)
                let source = source
                Task { await source.stop() }
                return
            }
            capture = .running
            wantsKeyframe = true
            log.notice("Streaming the GamePad screen")
        } else {
            capture = .failed(status, at: .now)
            log.notice("Can't stream the GamePad screen: \(String(describing: status), privacy: .public)")
        }
        for slot in requesters.keys {
            sendStatus(currentStatus(), slot)
        }
    }

    private func stopped(generation: Int) {
        guard generation == self.generation, case .running = capture else { return }
        log.notice("The GamePad window went away")
        encoder = nil
        lastPicture = nil
        capture = .failed(.noWindow, at: .now)
        for slot in requesters.keys {
            sendStatus(.noWindow, slot)
        }
    }

    private func stopCapture() {
        generation += 1
        capture = .stopped(since: .now)
        encoder = nil
        lastPicture = nil
        let source = source
        Task { await source.stop() }
        log.notice("Stopped streaming the GamePad screen")
    }

    private func received(_ picture: CVPixelBuffer, generation: Int) {
        guard generation == self.generation, case .running = capture else { return }
        lastPicture = picture
        encode(picture)
    }

    private func encode(_ picture: CVPixelBuffer) {
        guard let encoder else { return }
        inputNumber += 1
        lastSubmitted = .now
        let forceKeyframe = wantsKeyframe
        wantsKeyframe = false
        do {
            try encoder.encode(picture, time: CMTime(value: inputNumber, timescale: 600), forceKeyframe: forceKeyframe)
        } catch {
            log.error("Couldn't encode a picture: \(String(describing: error), privacy: .public)")
            wantsKeyframe = true
        }
    }

    private func makeEncoder() throws(VideoEncoder.EncoderError) -> VideoEncoder {
        let generation = generation
        return try VideoEncoder(settings: settings) { [weak self] _, result in
            guard let self else { return }
            queue.async { self.encoded(result, generation: generation) }
        }
    }

    private func encoded(_ result: Result<EncodedFrame, VideoEncoder.EncoderError>, generation: Int) {
        guard generation == self.generation else { return }
        let frame: EncodedFrame
        switch result {
        case .success(let encoded):
            frame = encoded
        case .failure(let error):
            log.error("The encoder failed: \(String(describing: error), privacy: .public)")
            wantsKeyframe = true
            return
        }
        frameNumber &+= 1
        guard let fragments = VideoFragment.split(frame.encoded(), frame: frameNumber) else {
            log.error("Dropped a frame too large to send")
            wantsKeyframe = true
            return
        }
        let slots = Set(requesters.keys)
        for fragment in fragments {
            send(fragment.encoded(), slots)
        }
    }
}

/// A picture handed from the capture's queue to the streamer's. CoreVideo buffers are safe to pass
/// between threads, but aren't marked Sendable.
private struct UncheckedPicture: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) { self.value = value }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
#endif
