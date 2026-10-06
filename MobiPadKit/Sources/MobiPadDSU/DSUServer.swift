import Foundation
import MobiPadProtocol
import Network
import os

/// Serves up to four controllers to emulators (such as Dolphin) over the DSU protocol.
///
/// It only listens on localhost, so controller input never leaves this Mac (NFR-05).
/// All state lives on `queue`; the public methods hop onto it, so they can be called from anywhere.
///
/// An emulator that supports DSU rumble asks how many motors each controller has, then sends rumble
/// a few times a second; every one goes to `onRumble`. The server keeps no rumble state: when the
/// emulator stops sending (it quit mid-rumble), the phone stops by itself.
public final class DSUServer: @unchecked Sendable {
    /// Dolphin re-registers every second; a client that stays silent this long is dropped.
    static let clientTimeout: TimeInterval = 5

    private let log = Logger(subsystem: "MobiPad", category: "dsu")
    private let queue = DispatchQueue(label: "MobiPad.DSUServer")
    private let port: UInt16
    private let onRumble: @Sendable (_ slot: Int, _ intensity: UInt8) -> Void
    private let serverID = UInt32.random(in: .min ... .max)
    private var listener: NWListener?
    private var slots = [Slot](repeating: Slot(), count: DSU.slotCount)
    private var clients: [ObjectIdentifier: Client] = [:]

    private struct Slot {
        /// Nil while no controller uses this slot.
        var state: ControllerState?
        var packetCounter: UInt32 = 0
    }

    private struct Client {
        let connection: NWConnection
        var subscribedSlots: Set<Int> = []
        var lastSeen = Date()
    }

    /// - Parameters:
    ///   - port: 0 lets the system pick a free port (useful in tests).
    ///   - onRumble: called on the server's queue for every rumble an emulator sends to a connected
    ///     controller. Intensity 0 stops it.
    public init(
        port: UInt16 = DSU.defaultPort,
        onRumble: @escaping @Sendable (_ slot: Int, _ intensity: UInt8) -> Void = { _, _ in }
    ) {
        self.port = port
        self.onRumble = onRumble
    }

    /// Starts listening and returns the port once the server is ready.
    public func start() async throws -> UInt16 {
        let parameters = NWParameters.udp
        parameters.requiredInterfaceType = .loopback
        let listener = if port == 0 {
            try NWListener(using: parameters)
        } else {
            try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        }
        queue.sync { self.listener = listener }

        return try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: resumeOnce.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): resumeOnce.resume(throwing: error)
                case .waiting(let error): resumeOnce.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            clients.values.forEach { $0.connection.cancel() }
            clients = [:]
        }
    }

    /// Sets a slot's controller state and sends it to subscribed emulators.
    public func update(slot: Int, state: ControllerState) {
        queue.async { [self] in
            guard slots.indices.contains(slot) else { return }
            slots[slot].state = state
            removeExpiredClients()
            let subscribers = clients.values.filter { $0.subscribedSlots.contains(slot) }
            guard !subscribers.isEmpty else { return }
            let data = padData(slot: slot)
            for client in subscribers {
                client.connection.send(content: data, completion: .idempotent)
            }
        }
    }

    /// Marks a slot as empty. Emulators remove the controller the next time they list ports.
    public func disconnect(slot: Int) {
        queue.async { [self] in
            guard slots.indices.contains(slot) else { return }
            slots[slot].state = nil
        }
    }

    // MARK: - On queue

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        clients[id] = Client(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.clients[id] = nil
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
                handle(data, from: connection)
            }
            receive(on: connection)
        }
    }

    private func handle(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var client = clients[id], let request = try? DSU.Request(decoding: data) else { return }
        client.lastSeen = Date()

        switch request {
        case .version:
            connection.send(content: DSU.versionResponse(serverID: serverID), completion: .idempotent)
        case .listPorts(let requested):
            for slot in requested {
                let info = DSU.portInfo(slot: slot, isConnected: slots[slot].state != nil, serverID: serverID)
                connection.send(content: info, completion: .idempotent)
            }
        case .subscribe(let requested):
            if !requested.isSubset(of: client.subscribedSlots) {
                log.notice("An emulator subscribed to slots \(requested.sorted().map { $0 + 1 }, privacy: .public)")
            }
            client.subscribedSlots.formUnion(requested)
            // Answer right away so the emulator doesn't wait for the next input change.
            for slot in requested where slots[slot].state != nil {
                connection.send(content: padData(slot: slot), completion: .idempotent)
            }
        case .motorInfo(let requested):
            for slot in requested.sorted() {
                let info = DSU.motorInfo(slot: slot, isConnected: slots[slot].state != nil, serverID: serverID)
                connection.send(content: info, completion: .idempotent)
            }
        case .rumble(let requested, let motor, let intensity):
            guard motor < DSU.motorCount else { break }
            for slot in requested.sorted() where slots[slot].state != nil {
                onRumble(slot, intensity)
            }
        }
        clients[id] = client
    }

    private func padData(slot: Int) -> Data {
        slots[slot].packetCounter &+= 1
        return DSU.padData(
            slot: slot,
            state: slots[slot].state ?? ControllerState(),
            packetCounter: slots[slot].packetCounter,
            timestampMicroseconds: DispatchTime.now().uptimeNanoseconds / 1000,
            serverID: serverID
        )
    }

    private func removeExpiredClients() {
        let cutoff = Date().addingTimeInterval(-Self.clientTimeout)
        for (id, client) in clients where client.lastSeen < cutoff {
            if !client.subscribedSlots.isEmpty {
                log.notice("An emulator stopped asking for slots \(client.subscribedSlots.sorted().map { $0 + 1 }, privacy: .public)")
            }
            client.connection.cancel()
            clients[id] = nil
        }
    }
}
