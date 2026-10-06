import Foundation
import MobiPadProtocol
import Network
import os

/// The Mac side of the connection: advertises itself with Bonjour and gives up to four
/// approved phones a controller slot each (FR-01, CR-02, CR-03, FR-10, NFR-06).
///
/// All state lives on `queue`; the public methods hop onto it, so they can be called from anywhere.
/// Log messages go to the unified log (subsystem "MobiPad"), visible in Console.app.
public final class ControllerHost: @unchecked Sendable {
    public static let slotCount = 4

    public struct Player: Sendable, Equatable {
        public let slot: Int
        public let name: String
        public var state = ControllerState()
        /// Half the round-trip time of the last ping (DR-03).
        public var latency: Duration?
    }

    /// A phone asking to connect that the user hasn't approved yet.
    public struct ApprovalRequest: Sendable, Hashable {
        /// The phone's public identity key. Store it to keep the phone approved across launches.
        public let identity: Data
        public let name: String
    }

    public struct Timing: Sendable {
        public var pingInterval: Duration = .seconds(1)
        /// A phone that stays silent this long loses its slot.
        public var timeout: Duration = .seconds(3)

        public init() {}
    }

    /// Called on the host's queue with every new state, or nil when a slot empties.
    public typealias Output = @Sendable (_ slot: Int, _ state: ControllerState?) -> Void

    private let log = Logger(subsystem: "MobiPad", category: "host")
    private let queue = DispatchQueue(label: "MobiPad.ControllerHost")
    private let service: NWListener.Service?
    private let timing: Timing
    private let onApprovalRequest: @Sendable (ApprovalRequest) -> Void
    private let output: Output
    private var listener: NWListener?
    private var timer: DispatchSourceTimer?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var approved: Set<Data>
    /// Denials last until the app quits, so a phone can always be approved later.
    private var denied: Set<Data> = []
    private var pending: Set<Data> = []
    /// The slot each phone last had, so it gets the same player number back after a dropout.
    private var previousSlots: [Data: Int] = [:]
    /// A pretend phone for checking an emulator's setup without an iPhone.
    private var testPlayer: Player?
    private var testTimer: DispatchSourceTimer?

    private struct Peer {
        let connection: NWConnection
        var lastHeard = ContinuousClock.now
        var identity: Data?
        var name = ""
        /// Set once the phone proves it owns its identity key, by sending a message that
        /// opens with the session key. Until then it only has `offeredSlot`, so a device
        /// that copied an approved phone's public key can't take that phone's slot.
        var player: Player?
        var offeredSlot: Int?
        var channel: SecureChannel?
        /// The phone's ephemeral key and our answer to it, to resend if the phone repeats its hello.
        var phoneEphemeral: Data?
        var welcome: Message?
        var lastSequence: UInt32?
        var rumbleSequence: UInt32 = 0
    }

    /// - Parameters:
    ///   - service: the Bonjour service to advertise; nil to skip advertising (tests).
    ///   - approvedPhones: identity keys of phones the user allowed before.
    ///   - onApprovalRequest: called on the host's queue, once per unknown phone, until
    ///     ``approve(_:)`` or ``deny(_:)`` answers it.
    public init(
        service: NWListener.Service? = NWListener.Service(type: MobiPadService.bonjourType),
        timing: Timing = Timing(),
        approvedPhones: Set<Data> = [],
        onApprovalRequest: @escaping @Sendable (ApprovalRequest) -> Void,
        output: @escaping Output
    ) {
        self.service = service
        self.timing = timing
        self.approved = approvedPhones
        self.onApprovalRequest = onApprovalRequest
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
        log.notice("Listening for phones on port \(port)")
        return port
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            listener?.cancel()
            listener = nil
            for id in Array(peers.keys) {
                remove(id, reason: "host stopped")
            }
            removeTestPlayer()
        }
    }

    /// The connected phones and the test player, ordered by slot.
    public func players() -> [Player] {
        queue.sync {
            (peers.values.compactMap(\.player) + [testPlayer].compactMap { $0 }).sorted { $0.slot < $1.slot }
        }
    }

    public static let testPlayerName = "Test controller"

    /// Adds a pretend player in the lowest free slot that circles its sticks and presses A, B, X
    /// and Y in turn (see ``testState(at:)``), to check an emulator's setup without a phone.
    /// Returns its slot, or nil when every slot is taken.
    public func startTestPlayer() -> Int? {
        queue.sync {
            if let testPlayer {
                return testPlayer.slot
            }
            guard let slot = freeSlots().first else { return nil }
            testPlayer = Player(slot: slot, name: Self.testPlayerName)
            log.notice("Test controller joined as player \(slot + 1)")

            let start = ContinuousClock.now
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 60)
            timer.setEventHandler { [weak self] in
                guard let self, var player = testPlayer else { return }
                player.state = Self.testState(at: (ContinuousClock.now - start).timeInterval)
                testPlayer = player
                output(player.slot, player.state)
            }
            timer.resume()
            testTimer = timer
            return slot
        }
    }

    public func stopTestPlayer() {
        queue.async { [self] in removeTestPlayer() }
    }

    /// The test player's input: sticks circle once every 2 seconds in opposite directions,
    /// A, B, X and Y take turns every half second, and the triggers pulse.
    static func testState(at seconds: TimeInterval) -> ControllerState {
        let angle = seconds * .pi
        let faceButtons: [ControllerState.Buttons] = [.a, .b, .x, .y]
        let trigger = UInt8(((1 - cos(angle)) / 2 * 255).rounded())
        return ControllerState(
            buttons: faceButtons[Int(seconds * 2) % faceButtons.count],
            leftStick: .init(normalizedX: cos(angle), normalizedY: sin(angle)),
            rightStick: .init(normalizedX: -cos(angle), normalizedY: -sin(angle)),
            leftTrigger: trigger,
            rightTrigger: trigger
        )
    }

    /// Lets the phone in. It joins with its next hello, within half a second.
    public func approve(_ identity: Data) {
        queue.async { [self] in
            approved.insert(identity)
            denied.remove(identity)
            pending.remove(identity)
        }
    }

    public func deny(_ identity: Data) {
        queue.async { [self] in
            denied.insert(identity)
            pending.remove(identity)
        }
    }

    /// Passes an emulator's rumble on to the phone in `slot`. Intensity 0 stops it. The test player
    /// has nothing to rumble.
    public func rumble(slot: Int, intensity: UInt8) {
        queue.async { [self] in
            guard let id = peers.first(where: { $0.value.player?.slot == slot })?.key else { return }
            peers[id]?.rumbleSequence &+= 1
            guard let peer = peers[id] else { return }
            sendSealed(.rumble(sequence: peer.rumbleSequence, intensity: intensity), to: peer)
        }
    }

    /// Forgets every approved phone and disconnects them; each has to be allowed again.
    public func revokeAllApprovals() {
        queue.async { [self] in
            approved = []
            for id in Array(peers.keys) {
                remove(id, reason: "approvals revoked")
            }
        }
    }

    // MARK: - On queue

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        peers[id] = Peer(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error): self?.remove(id, reason: "connection failed: \(error)")
            case .cancelled: self?.remove(id, reason: "connection closed")
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil else { return }
            if let data {
                handle(data, from: ObjectIdentifier(connection))
            }
            receive(on: connection)
        }
    }

    private func handle(_ data: Data, from id: ObjectIdentifier) {
        guard var peer = peers[id] else { return }
        let message: Message
        do {
            message = try Message(decoding: data)
        } catch {
            log.debug("Dropped an invalid datagram: \(String(describing: error), privacy: .public)")
            return
        }

        switch message {
        case .hello(let identity, let ephemeral, let name):
            peer.lastHeard = .now
            handleHello(&peer, id: id, identity: identity, ephemeral: ephemeral, name: name)
        case .sealed(let box):
            // Only authenticated messages keep a phone connected.
            guard let channel = peer.channel, let sessionMessage = try? channel.open(box) else {
                log.debug("Dropped a message that failed authentication")
                return
            }
            peer.lastHeard = .now
            if peer.player == nil, !activate(&peer, id: id) {
                return
            }
            handle(sessionMessage, peer: &peer, id: id)
        case .pending, .denied, .full, .welcome:
            return
        }
        if peers[id] != nil {
            peers[id] = peer
        }
    }

    private func handleHello(_ peer: inout Peer, id: ObjectIdentifier, identity: Data, ephemeral: Data, name: String) {
        if denied.contains(identity) {
            send(.denied, to: peer)
            return
        }
        guard approved.contains(identity) else {
            if pending.insert(identity).inserted {
                log.notice("\(name, privacy: .public) asks to connect")
                onApprovalRequest(ApprovalRequest(identity: identity, name: name))
            }
            send(.pending, to: peer)
            return
        }
        // A repeated hello means our welcome was lost; the phone still has the same keys.
        if let welcome = peer.welcome, peer.phoneEphemeral == ephemeral {
            send(welcome, to: peer)
            return
        }
        guard let slot = peer.player?.slot ?? offerSlot(for: identity, excluding: id) else {
            log.notice("\(name, privacy: .public) turned away: all \(Self.slotCount) slots are taken")
            send(.full, to: peer)
            return
        }
        let macEphemeral = SecureChannel.PrivateKey()
        guard let channel = try? SecureChannel.mac(ephemeral: macEphemeral, phoneIdentity: identity, phoneEphemeral: ephemeral) else {
            log.error("\(name, privacy: .public) sent unusable keys")
            return
        }
        let welcome = Message.welcome(
            ephemeral: macEphemeral.publicKey.rawRepresentation,
            sealed: channel.seal(.slot(UInt8(slot)))
        )
        peer.identity = identity
        peer.name = name
        peer.offeredSlot = slot
        peer.channel = channel
        peer.phoneEphemeral = ephemeral
        peer.welcome = welcome
        peer.lastSequence = nil
        send(welcome, to: peer)
    }

    /// Gives an authenticated phone its slot. Returns false when every slot got taken meanwhile.
    private func activate(_ peer: inout Peer, id: ObjectIdentifier) -> Bool {
        guard let identity = peer.identity, let offeredSlot = peer.offeredSlot else { return false }
        if let old = activePeer(with: identity, excluding: id) {
            // The same phone on a new connection, after a network change: it keeps its slot.
            peer.player = old.value.player
            peers[old.key] = nil
            old.value.connection.cancel()
        } else {
            let free = freeSlots(excluding: id)
            guard let slot = free.contains(offeredSlot) ? offeredSlot : free.first else {
                send(.full, to: peer)
                return false
            }
            peer.player = Player(slot: slot, name: peer.name)
            if slot != offeredSlot {
                sendSealed(.slot(UInt8(slot)), to: peer)
            }
        }
        let slot = peer.player!.slot
        let name = peer.name
        previousSlots[identity] = slot
        log.notice("\(name, privacy: .public) joined as player \(slot + 1)")
        return true
    }

    private func handle(_ message: SessionMessage, peer: inout Peer, id: ObjectIdentifier) {
        switch message {
        case .state(let sequence, let state):
            guard var player = peer.player else { return }
            if let last = peer.lastSequence, !SessionMessage.isSequence(sequence, newerThan: last) { return }
            peer.lastSequence = sequence
            player.state = state
            peer.player = player
            output(player.slot, state)

        case .goodbye:
            peers[id] = peer
            remove(id, reason: "disconnected on the phone")

        case .pong(let token):
            let roundTrip = DispatchTime.now().uptimeNanoseconds &- token
            peer.player?.latency = .nanoseconds(Int64(clamping: roundTrip / 2))

        case .ping(let token):
            sendSealed(.pong(token: token), to: peer)

        case .slot, .rumble:
            break
        }
    }

    /// The slot this phone has on an older connection (after a network change),
    /// otherwise its previous slot if free, otherwise the lowest free slot.
    private func offerSlot(for identity: Data, excluding id: ObjectIdentifier) -> Int? {
        if let old = activePeer(with: identity, excluding: id) {
            return old.value.player?.slot
        }
        let free = freeSlots(excluding: id)
        return previousSlots[identity].flatMap { free.contains($0) ? $0 : nil } ?? free.first
    }

    private func activePeer(with identity: Data, excluding id: ObjectIdentifier) -> (key: ObjectIdentifier, value: Peer)? {
        peers.first { $0.key != id && $0.value.identity == identity && $0.value.player != nil }
    }

    private func freeSlots(excluding id: ObjectIdentifier? = nil) -> [Int] {
        var taken = Set(peers.filter { $0.key != id }.values.compactMap(\.player?.slot))
        if let testPlayer {
            taken.insert(testPlayer.slot)
        }
        return (0..<Self.slotCount).filter { !taken.contains($0) }
    }

    private func removeTestPlayer() {
        testTimer?.cancel()
        testTimer = nil
        guard let player = testPlayer else { return }
        testPlayer = nil
        log.notice("Test controller left player \(player.slot + 1)")
        output(player.slot, nil)
    }

    private func tick() {
        let now = ContinuousClock.now
        for (id, peer) in peers {
            if now - peer.lastHeard > timing.timeout {
                remove(id, reason: "timed out")
            } else if peer.player != nil {
                sendSealed(.ping(token: DispatchTime.now().uptimeNanoseconds), to: peer)
            }
        }
    }

    private func remove(_ id: ObjectIdentifier, reason: String) {
        guard let peer = peers.removeValue(forKey: id) else { return }
        peer.connection.cancel()
        if let player = peer.player {
            log.notice("\(player.name, privacy: .public) left player \(player.slot + 1): \(reason, privacy: .public)")
            output(player.slot, nil)
        }
    }

    private func send(_ message: Message, to peer: Peer) {
        peer.connection.send(content: message.encoded(), completion: .idempotent)
    }

    private func sendSealed(_ message: SessionMessage, to peer: Peer) {
        guard let channel = peer.channel else { return }
        send(.sealed(channel.seal(message)), to: peer)
    }
}
