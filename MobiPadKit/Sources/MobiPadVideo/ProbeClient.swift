import CoreVideo
import Foundation
import Network
import os

/// The phone's side of the stream probe: subscribes to a Mac running the StreamProbe tool, puts the
/// frames back together, decodes them, and reports the first frame in which the marker switched.
///
/// All state lives on `queue`; ``onPicture`` is called there too.
public final class ProbeClient: @unchecked Sendable {
    public struct Status: Sendable, Equatable {
        public var framesDecoded = 0
        public var framesLost = 0
        public var lastError: String?

        public init() {}
    }

    private let log = Logger(subsystem: "MobiPad", category: "probe")
    private let queue = DispatchQueue(label: "MobiPad.ProbeClient", qos: .userInteractive)
    private let endpoint: NWEndpoint
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var receiver = VideoReceiver()
    private let decoder = VideoDecoder()
    private var markerWhite: Bool?
    private var status = Status()
    private var decodeMicroseconds: [Int] = []
    private var lastKeyframeRequest = ContinuousClock.now - .seconds(1)

    /// Each decoded picture, on the client's queue, to show on screen.
    private let onPicture: @Sendable (CVPixelBuffer) -> Void
    private let onStatus: @Sendable (Status) -> Void

    public init(
        to endpoint: NWEndpoint,
        onPicture: @escaping @Sendable (CVPixelBuffer) -> Void,
        onStatus: @escaping @Sendable (Status) -> Void
    ) {
        self.endpoint = endpoint
        self.onPicture = onPicture
        self.onStatus = onStatus
    }

    public func start() {
        queue.async { [self] in
            let connection = NWConnection(to: endpoint, using: .udp)
            connection.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.fail("Connection failed: \(error)")
                }
            }
            connection.start(queue: queue)
            self.connection = connection
            receive(on: connection)

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            connection?.cancel()
            connection = nil
        }
    }

    // MARK: - On queue

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.connection === connection else { return }
            if let error {
                fail("Receive failed: \(error)")
                return
            }
            if let data {
                handle(data)
            }
            receive(on: connection)
        }
    }

    private func handle(_ data: Data) {
        guard case .fragment(let fragment)? = try? ProbeMessage(decoding: data) else {
            log.debug("Dropped a datagram that isn't a fragment")
            return
        }
        let output = receiver.receive(fragment)
        if output.wantsKeyframe, ContinuousClock.now - lastKeyframeRequest > .milliseconds(100) {
            lastKeyframeRequest = .now
            send(.keyframe)
        }
        guard let frame = output.frame else { return }

        let start = ContinuousClock.now
        let picture: CVPixelBuffer
        do {
            picture = try decoder.decode(frame)
        } catch {
            fail("Decode failed: \(error)")
            receiver.requireKeyframe()
            send(.keyframe)
            return
        }
        let elapsed = ContinuousClock.now - start
        decodeMicroseconds.append(Int(elapsed.components.attoseconds / 1_000_000_000_000) + Int(elapsed.components.seconds) * 1_000_000)
        status.framesDecoded += 1

        // Reported before the picture goes to the screen, so drawing doesn't count towards the delay.
        let white = LatencyMarker.isWhite(picture)
        if white != markerWhite {
            markerWhite = white
            send(.seen(white: white))
        }
        onPicture(picture)
    }

    private func tick() {
        send(.subscribe)
        let mean = decodeMicroseconds.isEmpty ? 0 : decodeMicroseconds.reduce(0, +) / decodeMicroseconds.count
        decodeMicroseconds.removeAll(keepingCapacity: true)
        send(.stats(.init(
            completed: UInt32(clamping: receiver.completedFrames),
            lost: UInt32(clamping: receiver.lostFrames),
            decoded: UInt32(clamping: status.framesDecoded),
            meanDecodeMicroseconds: UInt32(clamping: mean)
        )))
        status.framesLost = receiver.lostFrames
        onStatus(status)
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        status.lastError = message
        onStatus(status)
    }

    private func send(_ message: ProbeMessage) {
        connection?.send(content: message.encoded(), completion: .idempotent)
    }
}
