import Foundation
import MobiPadProtocol
import Network

/// The phone side of the connection: claims a slot on the Mac and streams controller state.
///
/// It reconnects on its own when the Mac goes quiet (FR-09), and resends the current state
/// regularly so that a lost datagram is corrected within one resend interval.
/// All state lives on `queue`; the public methods hop onto it, so they can be called from anywhere.
public final class ControllerLink: @unchecked Sendable {
    public enum Status: Sendable, Equatable {
        case connecting
        case connected(slot: Int)
        /// The Mac has four phones already. The link keeps asking, and joins when a slot frees up.
        case full
        case disconnected
    }

    public struct Timing: Sendable {
        public var helloInterval: Duration = .milliseconds(500)
        public var resendInterval: Duration = .milliseconds(50)
        /// Without any message from the Mac for this long, the link reconnects.
        public var timeout: Duration = .seconds(3)

        public init() {}
    }

    private let queue = DispatchQueue(label: "MobiPad.ControllerLink")
    private let endpoint: NWEndpoint
    private let clientID: UUID
    private let name: String
    private let timing: Timing
    private let onStatus: @Sendable (Status) -> Void

    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var status = Status.disconnected
    private var state = ControllerState()
    private var sequence: UInt32 = 0
    private var lastHeard = ContinuousClock.now
    private var lastSent = ContinuousClock.now

    /// - Parameters:
    ///   - clientID: stays the same across launches, so the Mac can give the phone its slot back.
    ///   - onStatus: called on the link's queue whenever the status changes.
    public init(
        to endpoint: NWEndpoint,
        clientID: UUID,
        name: String,
        timing: Timing = Timing(),
        onStatus: @escaping @Sendable (Status) -> Void
    ) {
        self.endpoint = endpoint
        self.clientID = clientID
        self.name = name
        self.timing = timing
        self.onStatus = onStatus
    }

    public func connect() {
        queue.async { [self] in
            guard timer == nil else { return }
            setStatus(.connecting)
            openConnection()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: timing.resendInterval.timeInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    /// Sends a new controller state right away when connected.
    public func send(_ state: ControllerState) {
        queue.async { [self] in
            self.state = state
            if case .connected = status {
                sendState()
            }
        }
    }

    /// Tells the Mac this phone is leaving (FR-02) and stops.
    public func disconnect() {
        queue.async { [self] in
            if case .connected = status {
                send(.goodbye)
            }
            timer?.cancel()
            timer = nil
            connection?.cancel()
            connection = nil
            setStatus(.disconnected)
        }
    }

    // MARK: - On queue

    private func openConnection() {
        connection?.cancel()
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .failed = state, self.connection === connection {
                // The next tick opens a new connection.
                self.connection = nil
            }
        }
        connection.start(queue: queue)
        self.connection = connection
        lastHeard = .now
        lastSent = .now - timing.helloInterval
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil, self.connection === connection else { return }
            if let data, let message = try? Message(decoding: data) {
                handle(message)
            }
            receive(on: connection)
        }
    }

    private func handle(_ message: Message) {
        lastHeard = .now
        switch message {
        case .welcome(let slot):
            if status != .connected(slot: Int(slot)) {
                setStatus(.connected(slot: Int(slot)))
                sendState()
            }
        case .full:
            setStatus(.full)
        case .ping(let token):
            send(.pong(token: token))
        case .state, .hello, .goodbye, .pong:
            break
        }
    }

    private func tick() {
        let now = ContinuousClock.now
        if connection == nil || now - lastHeard > timing.timeout {
            setStatus(.connecting)
            openConnection()
        }
        switch status {
        case .connected:
            if now - lastSent >= timing.resendInterval {
                sendState()
            }
        case .connecting, .full:
            if now - lastSent >= timing.helloInterval {
                send(.hello(clientID: clientID, name: name))
                lastSent = now
            }
        case .disconnected:
            break
        }
    }

    private func sendState() {
        sequence &+= 1
        send(.state(sequence: sequence, state))
        lastSent = .now
    }

    private func send(_ message: Message) {
        connection?.send(content: message.encoded(), completion: .idempotent)
    }

    private func setStatus(_ newStatus: Status) {
        guard newStatus != status else { return }
        status = newStatus
        onStatus(newStatus)
    }
}
