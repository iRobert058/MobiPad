import CoreVideo
import Foundation
import Network
import os

/// The phone's side of the stream probe: subscribes to a Mac running the StreamProbe tool, puts the
/// frames back together, decodes them, and reports the first frame in which the marker switched.
///
/// All state lives on `queue`; decoding happens on a ``VideoPlayer``'s.
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
    private var player: VideoPlayer!
    /// Touched only on the player's queue, in `onPicture`.
    private let marker = MarkerState()
    private var status = Status()
    private var totals = VideoPlayer.Stats()

    private let onStatus: @Sendable (Status) -> Void

    private final class MarkerState: @unchecked Sendable {
        var white: Bool?
    }

    /// - Parameter onPicture: each decoded picture, on the player's queue, to show on screen.
    public init(
        to endpoint: NWEndpoint,
        onPicture: @escaping @Sendable (CVPixelBuffer) -> Void,
        onStatus: @escaping @Sendable (Status) -> Void
    ) {
        self.endpoint = endpoint
        self.onStatus = onStatus
        let marker = marker
        player = VideoPlayer(
            onPicture: { [weak self] picture in
                // Reported before the picture goes to the screen, so drawing doesn't count towards the delay.
                let white = LatencyMarker.isWhite(picture)
                if white != marker.white {
                    marker.white = white
                    self?.send(.seen(white: white))
                }
                onPicture(picture)
            },
            requestKeyframe: { [weak self] in self?.send(.keyframe) }
        )
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
        player.receive(fragment.encoded())
    }

    private func tick() {
        send(.subscribe)
        let stats = player.takeStats()
        totals.completed = stats.completed
        totals.lost = stats.lost
        totals.decoded += stats.decoded
        send(.stats(.init(
            completed: UInt32(clamping: totals.completed),
            lost: UInt32(clamping: totals.lost),
            decoded: UInt32(clamping: totals.decoded),
            meanDecodeMicroseconds: UInt32(clamping: stats.meanDecodeMicroseconds)
        )))
        status.framesDecoded = totals.decoded
        status.framesLost = totals.lost
        onStatus(status)
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        status.lastError = message
        onStatus(status)
    }

    /// From any queue: a connection can send from anywhere.
    private func send(_ message: ProbeMessage) {
        queue.async { [self] in
            connection?.send(content: message.encoded(), completion: .idempotent)
        }
    }
}
