import Foundation
import MobiPadProtocol
import Network

/// The Mac side of the connection: advertises itself with Bonjour and gives up to four
/// phones a controller slot each (FR-01, CR-02, FR-10).
///
/// All state lives on `queue`; the public methods hop onto it, so they can be called from anywhere.
public final class ControllerHost: @unchecked Sendable {
    public static let slotCount = 4

    public struct Player: Sendable, Equatable {
        public let slot: Int
        public let name: String
        public var state = ControllerState()
        /// Half the round-trip time of the last ping (DR-03).
        public var latency: Duration?
    }

    public struct Timing: Sendable {
        public var pingInterval: Duration = .seconds(1)
        /// A phone that stays silent this long loses its slot.
        public var timeout: Duration = .seconds(3)

        public init() {}
    }

    /// Called on the host's queue with every new state, or nil when a slot empties.
    public typealias Output = @Sendable (_ slot: Int, _ state: ControllerState?) -> Void

    private let queue = DispatchQueue(label: "MobiPad.ControllerHost")
    private let service: NWListener.Service?
    private let timing: Timing
    private let output: Output
    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var peers: [ObjectIdentifier: Peer] = [:]
    /// The slot each phone last had, so it gets the same player number back after a dropout.
    private var previousSlots: [UUID: Int] = [:]

    private struct Peer {
        let connection: NWConnection
        var lastHeard = ContinuousClock.now
        var clientID: UUID?
        var player: Player?
        var lastSequence: UInt32?
    }

    /// - Parameter service: the Bonjour service to advertise; nil to skip advertising (tests).
    public init(
        service: NWListener.Service? = NWListener.Service(type: MobiPadService.bonjourType),
        timing: Timing = Timing(),
        output: @escaping Output
    ) {
        self.service = service
        self.timing = timing
        self.output = output
    }

    /// Starts listening on a free port and returns it once the host is ready.
    public func start() async throws -> UInt16 {
        let listener = try NWListener(using: .udp)
        listener.service = service
        queue.sync { self.listener = listener }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: resumeOnce.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): resumeOnce.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }

        queue.sync {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: timing.pingInterval.timeInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
        return port
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            listener?.cancel()
            listener = nil
            for id in Array(peers.keys) {
                remove(id)
            }
        }
    }

    /// The connected phones, ordered by slot.
    public func players() -> [Player] {
        queue.sync { peers.values.compactMap(\.player).sorted { $0.slot < $1.slot } }
    }

    // MARK: - On queue

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        peers[id] = Peer(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.remove(id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil else { return }
            if let data, let message = try? Message(decoding: data) {
                handle(message, from: ObjectIdentifier(connection))
            }
            receive(on: connection)
        }
    }

    private func handle(_ message: Message, from id: ObjectIdentifier) {
        guard var peer = peers[id] else { return }
        peer.lastHeard = .now
        defer { if peers[id] != nil { peers[id] = peer } }

        switch message {
        case .hello(let clientID, let name):
            if peer.player == nil {
                peer.clientID = clientID
                guard let player = claimSlot(for: clientID, name: name, excluding: id) else {
                    send(.full, to: peer)
                    return
                }
                peer.player = player
                previousSlots[clientID] = player.slot
            }
            // Also answers repeated hellos, in case the first welcome was lost.
            send(.welcome(slot: UInt8(peer.player!.slot)), to: peer)

        case .state(let sequence, let state):
            guard var player = peer.player else { return }
            if let last = peer.lastSequence, !Message.isSequence(sequence, newerThan: last) { return }
            peer.lastSequence = sequence
            player.state = state
            peer.player = player
            output(player.slot, state)

        case .goodbye:
            peers[id] = peer
            remove(id)

        case .ping(let token):
            send(.pong(token: token), to: peer)

        case .pong(let token):
            let roundTrip = DispatchTime.now().uptimeNanoseconds &- token
            peer.player?.latency = .nanoseconds(Int64(clamping: roundTrip / 2))

        case .welcome, .full:
            break
        }
    }

    /// Reuses the slot this phone had on an older connection (after a network change),
    /// otherwise its previous slot if free, otherwise the lowest free slot.
    private func claimSlot(for clientID: UUID, name: String, excluding id: ObjectIdentifier) -> Player? {
        if let old = peers.first(where: { $0.key != id && $0.value.clientID == clientID }),
           let player = old.value.player {
            peers[old.key] = nil
            old.value.connection.cancel()
            return player
        }
        let taken = Set(peers.values.compactMap(\.player?.slot))
        let free = (0..<Self.slotCount).filter { !taken.contains($0) }
        let slot = previousSlots[clientID].flatMap { free.contains($0) ? $0 : nil } ?? free.first
        return slot.map { Player(slot: $0, name: name) }
    }

    private func tick() {
        let now = ContinuousClock.now
        for (id, peer) in peers {
            if now - peer.lastHeard > timing.timeout {
                remove(id)
            } else if peer.player != nil {
                send(.ping(token: DispatchTime.now().uptimeNanoseconds), to: peer)
            }
        }
    }

    private func remove(_ id: ObjectIdentifier) {
        guard let peer = peers.removeValue(forKey: id) else { return }
        peer.connection.cancel()
        if let player = peer.player {
            output(player.slot, nil)
        }
    }

    private func send(_ message: Message, to peer: Peer) {
        peer.connection.send(content: message.encoded(), completion: .idempotent)
    }
}
