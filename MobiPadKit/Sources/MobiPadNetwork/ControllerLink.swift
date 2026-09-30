import Foundation
import MobiPadProtocol
import Network
import os

/// The phone side of the connection: gets approved by the Mac, claims a slot and streams
/// controller state over an encrypted session.
///
/// It reconnects on its own when the Mac goes quiet (FR-09), and resends the current state
/// regularly so that a lost datagram is corrected within one resend interval.
/// All state lives on `queue`; the public methods hop onto it, so they can be called from anywhere.
public final class ControllerLink: @unchecked Sendable {
    public enum Status: Sendable, Equatable {
        case connecting
        /// The Mac is asking its user whether to allow this phone.
        case waitingForApproval
        case connected(slot: Int)
        /// The Mac has four phones already. The link keeps asking, and joins when a slot frees up.
        case full
        /// The Mac's user denied this phone. Restarting the Mac app lets it ask again.
        case denied
        case disconnected
    }

    public struct Timing: Sendable {
        public var helloInterval: Duration = .milliseconds(500)
        public var resendInterval: Duration = .milliseconds(50)
        /// Without any message from the Mac for this long, the link reconnects.
        public var timeout: Duration = .seconds(3)

        public init() {}
    }

    private let log = Logger(subsystem: "MobiPad", category: "link")
    private let queue = DispatchQueue(label: "MobiPad.ControllerLink")
    private let endpoint: NWEndpoint
    private let identity: SecureChannel.PrivateKey
    private let name: String
    private let timing: Timing
    private let onStatus: @Sendable (Status) -> Void

    private var connection: NWConnection?
    /// Fresh for every connection, so every connection gets its own session key.
    private var ephemeral = SecureChannel.PrivateKey()
    private var channel: SecureChannel?
    private var timer: DispatchSourceTimer?
    private var status = Status.disconnected
    private var state = ControllerState()
    private var sequence: UInt32 = 0
    private var lastHeard = ContinuousClock.now
    private var lastSent = ContinuousClock.now

    /// - Parameters:
    ///   - identity: this phone's long-term key; the Mac remembers it once the user allows the phone.
    ///   - onStatus: called on the link's queue whenever the status changes.
    public init(
        to endpoint: NWEndpoint,
        identity: SecureChannel.PrivateKey,
        name: String,
        timing: Timing = Timing(),
        onStatus: @escaping @Sendable (Status) -> Void
    ) {
        self.endpoint = endpoint
        self.identity = identity
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
                sendSealed(.goodbye)
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
            if case .failed(let error) = state, self.connection === connection {
                log.notice("Connection failed: \(error, privacy: .public)")
                // The next tick opens a new connection.
                self.connection = nil
            }
        }
        connection.start(queue: queue)
        self.connection = connection
        ephemeral = SecureChannel.PrivateKey()
        channel = nil
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
        switch message {
        case .welcome(let macEphemeral, let sealed):
            guard let channel = try? SecureChannel.phone(identity: identity, ephemeral: ephemeral, macEphemeral: macEphemeral),
                  case .slot(let slot)? = try? channel.open(sealed)
            else {
                log.error("Ignored a welcome that failed authentication")
                return
            }
            lastHeard = .now
            self.channel = channel
            if status != .connected(slot: Int(slot)) {
                log.notice("Connected as player \(slot + 1)")
                setStatus(.connected(slot: Int(slot)))
                sendState()
            }
        case .pending:
            lastHeard = .now
            setStatus(.waitingForApproval)
        case .denied:
            lastHeard = .now
            setStatus(.denied)
        case .full:
            lastHeard = .now
            setStatus(.full)
        case .sealed(let box):
            guard let channel, let sessionMessage = try? channel.open(box) else { return }
            lastHeard = .now
            switch sessionMessage {
            case .ping(let token):
                sendSealed(.pong(token: token))
            case .slot(let slot):
                // The offered slot was taken by another phone meanwhile.
                setStatus(.connected(slot: Int(slot)))
            case .state, .goodbye, .pong:
                break
            }
        case .hello:
            break
        }
    }

    private func tick() {
        let now = ContinuousClock.now
        if connection == nil || now - lastHeard > timing.timeout {
            if status != .connecting {
                log.notice("No answer from the Mac; reconnecting")
            }
            setStatus(.connecting)
            openConnection()
        }
        switch status {
        case .connected:
            if now - lastSent >= timing.resendInterval {
                sendState()
            }
        case .connecting, .waitingForApproval, .full, .denied:
            if now - lastSent >= timing.helloInterval {
                send(.hello(identity: identity.publicKey.rawRepresentation, ephemeral: ephemeral.publicKey.rawRepresentation, name: name))
                lastSent = now
            }
        case .disconnected:
            break
        }
    }

    private func sendState() {
        sequence &+= 1
        sendSealed(.state(sequence: sequence, state))
        lastSent = .now
    }

    private func sendSealed(_ message: SessionMessage) {
        guard let channel else { return }
        send(.sealed(channel.seal(message)))
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
