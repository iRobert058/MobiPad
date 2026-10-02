import Foundation
import MobiPadProtocol
import Network
import Testing
@testable import MobiPadNetwork

/// Real phone links talking to a real host over UDP on localhost, without Bonjour.
@Suite(.timeLimit(.minutes(1)))
struct ControllerNetworkTests {
    @Test func phoneJoinsAndStreamsState() async throws {
        let rig = try await Rig()
        let phone = rig.phone(name: "Ana")
        try await phone.waitForStatus(.connected(slot: 0))

        phone.link.send(ControllerState(buttons: [.a]))
        try await rig.outputs.wait { $0.contains { $0.slot == 0 && $0.state?.buttons == [.a] } }
        #expect(rig.host.players().map(\.name) == ["Ana"])
    }

    @Test func unknownPhoneWaitsForApproval() async throws {
        let rig = try await Rig(autoApprove: false)
        let phone = rig.phone(name: "Ana")
        try await phone.waitForStatus(.waitingForApproval)
        try await rig.requests.wait { $0.map(\.name) == ["Ana"] }
        #expect(rig.host.players().isEmpty)

        rig.host.approve(phone.identity.publicKey.rawRepresentation)
        try await phone.waitForStatus(.connected(slot: 0))
        // Asked only once, although the phone kept saying hello.
        #expect(rig.requests.snapshot.count == 1)
    }

    @Test func deniedPhoneIsTurnedAway() async throws {
        let rig = try await Rig(autoApprove: false)
        let phone = rig.phone()
        try await rig.requests.wait { !$0.isEmpty }
        rig.host.deny(phone.identity.publicKey.rawRepresentation)
        try await phone.waitForStatus(.denied)
    }

    @Test func previouslyApprovedPhoneJoinsWithoutAsking() async throws {
        let identity = SecureChannel.PrivateKey()
        let rig = try await Rig(autoApprove: false, approvedPhones: [identity.publicKey.rawRepresentation])
        let phone = rig.phone(identity: identity)
        try await phone.waitForStatus(.connected(slot: 0))
        #expect(rig.requests.snapshot.isEmpty)
    }

    @Test func revokingApprovalsDisconnectsPhones() async throws {
        let rig = try await Rig(autoApprove: false)
        let phone = rig.phone()
        try await rig.requests.wait { !$0.isEmpty }
        rig.host.approve(phone.identity.publicKey.rawRepresentation)
        try await phone.waitForStatus(.connected(slot: 0))

        rig.host.revokeAllApprovals()
        try await rig.outputs.wait { $0.contains { $0.slot == 0 && $0.state == nil } }
        try await phone.waitForStatus(.waitingForApproval)
    }

    @Test func fourPhonesGetTheirOwnSlotsAndAFifthIsTurnedAway() async throws {
        let rig = try await Rig()
        let phones = (0..<4).map { _ in rig.phone() }
        for phone in phones {
            try await phone.statuses.wait { $0.contains { if case .connected = $0 { true } else { false } } }
        }
        #expect(rig.host.players().map(\.slot) == [0, 1, 2, 3])

        let fifth = rig.phone()
        try await fifth.waitForStatus(.full)

        // The fifth phone takes over the slot of the first phone that leaves.
        guard case .connected(let freedSlot) = phones[2].statuses.snapshot.last else {
            Issue.record("phone not connected"); return
        }
        phones[2].link.disconnect()
        try await fifth.waitForStatus(.connected(slot: freedSlot))
    }

    @Test func leavingEmptiesTheSlot() async throws {
        let rig = try await Rig()
        let phone = rig.phone()
        try await phone.waitForStatus(.connected(slot: 0))

        phone.link.disconnect()
        try await rig.outputs.wait { $0.contains { $0.slot == 0 && $0.state == nil } }
        #expect(rig.host.players().isEmpty)
    }

    @Test func returningPhoneGetsItsSlotBack() async throws {
        let rig = try await Rig()
        let first = rig.phone()
        try await first.waitForStatus(.connected(slot: 0))
        let second = rig.phone()
        try await second.waitForStatus(.connected(slot: 1))
        first.link.disconnect()
        second.link.disconnect()
        try await rig.outputs.wait { $0.filter { $0.state == nil }.count == 2 }

        // Slot 0 is free, but the second phone had slot 1.
        let returning = rig.phone(identity: second.identity)
        try await returning.waitForStatus(.connected(slot: 1))
    }

    @Test func testPlayerTakesAFreeSlotAndStreams() async throws {
        let rig = try await Rig()
        let phone = rig.phone(name: "Ana")
        try await phone.waitForStatus(.connected(slot: 0))

        #expect(rig.host.startTestPlayer() == 1)
        #expect(rig.host.startTestPlayer() == 1) // already running
        try await rig.outputs.wait { $0.filter { $0.slot == 1 && $0.state != nil }.count >= 5 }
        #expect(rig.host.players().map(\.name) == ["Ana", ControllerHost.testPlayerName])

        rig.host.stopTestPlayer()
        try await rig.outputs.wait { $0.contains { $0.slot == 1 && $0.state == nil } }
        #expect(rig.host.players().map(\.name) == ["Ana"])
    }

    @Test func testPlayerCountsTowardTheFourSlots() async throws {
        let rig = try await Rig()
        #expect(rig.host.startTestPlayer() == 0)
        let phones = (0..<3).map { _ in rig.phone() }
        for phone in phones {
            try await phone.statuses.wait { $0.contains { if case .connected = $0 { true } else { false } } }
        }
        try await rig.phone().waitForStatus(.full)
    }

    @Test func testPlayerFollowsItsPattern() {
        let start = ControllerHost.testState(at: 0)
        #expect(start.buttons == [.a])
        #expect(start.leftStick == .init(x: 32767, y: 0))
        #expect(start.rightStick == .init(x: -32767, y: 0))
        #expect(start.leftTrigger == 0)

        let quarter = ControllerHost.testState(at: 0.5)
        #expect(quarter.buttons == [.b])
        #expect(quarter.leftStick == .init(x: 0, y: 32767)) // up

        let half = ControllerHost.testState(at: 1)
        #expect(half.buttons == [.x])
        #expect(half.leftTrigger == 255)
        #expect(ControllerHost.testState(at: 1.5).buttons == [.y])
        #expect(ControllerHost.testState(at: 2).buttons == [.a])
    }

    @Test func measuresLatency() async throws {
        let rig = try await Rig()
        let phone = rig.phone()
        try await phone.waitForStatus(.connected(slot: 0))
        try await waitUntil { rig.host.players().first?.latency != nil }
    }

    @Test func silentPhoneLosesItsSlot() async throws {
        let rig = try await Rig()
        // A phone that completes the handshake and then goes quiet, like one that lost Wi-Fi.
        let socket = RawSocket(port: rig.port)
        let identity = SecureChannel.PrivateKey()
        let ephemeral = SecureChannel.PrivateKey()
        let macEphemeral = try await socket.handshake(
            .hello(identity: identity.publicKey.rawRepresentation, ephemeral: ephemeral.publicKey.rawRepresentation, name: "Gone")
        )
        let channel = try SecureChannel.phone(identity: identity, ephemeral: ephemeral, macEphemeral: macEphemeral)
        socket.send(.sealed(channel.seal(.state(sequence: 1, ControllerState()))))

        try await waitUntil { rig.host.players().count == 1 }
        try await rig.outputs.wait { $0.contains { $0.slot == 0 && $0.state == nil } }
        #expect(rig.host.players().isEmpty)
    }

    /// Someone on the network who copied an approved phone's public key (it's sent in the
    /// clear) gets a welcome, but can't send input or take the real phone's slot.
    @Test func impostorCantSendInputOrTakeTheSlot() async throws {
        let rig = try await Rig()
        let phone = rig.phone()
        try await phone.waitForStatus(.connected(slot: 0))

        let socket = RawSocket(port: rig.port)
        let ephemeral = SecureChannel.PrivateKey()
        let macEphemeral = try await socket.handshake(
            .hello(identity: phone.identity.publicKey.rawRepresentation, ephemeral: ephemeral.publicKey.rawRepresentation, name: "Impostor")
        )
        // Without the phone's private key, the impostor can only derive a wrong session key.
        let wrongChannel = try SecureChannel.phone(identity: SecureChannel.PrivateKey(), ephemeral: ephemeral, macEphemeral: macEphemeral)
        for sequence in 1...5 {
            socket.send(.sealed(wrongChannel.seal(.state(sequence: UInt32(sequence), ControllerState(buttons: [.a])))))
        }

        try await Task.sleep(for: .milliseconds(400))
        #expect(!rig.outputs.snapshot.contains { $0.state?.buttons == [.a] })
        #expect(rig.host.players().map(\.name) == ["Phone"])
        #expect(phone.statuses.snapshot.last == .connected(slot: 0))
    }

    /// The Mac's own sealed messages, sent back to it, mustn't count as proof of owning the key.
    @Test func impostorCantReflectTheMacsMessages() async throws {
        let rig = try await Rig()
        let phone = rig.phone()
        try await phone.waitForStatus(.connected(slot: 0))

        let socket = RawSocket(port: rig.port)
        let welcome = try await socket.welcome(
            .hello(identity: phone.identity.publicKey.rawRepresentation, ephemeral: SecureChannel.PrivateKey().publicKey.rawRepresentation, name: "Impostor")
        )
        socket.send(.sealed(welcome.sealed))

        // A player gets pinged every 50 ms; the impostor must not become one.
        var receivedSealed = false
        while let message = try? await socket.receive(timeout: .milliseconds(400)) {
            if case .sealed = message { receivedSealed = true }
        }
        #expect(!receivedSealed)
        // The real phone was never pushed out.
        let statuses = phone.statuses.snapshot
        let joined = statuses.firstIndex(of: .connected(slot: 0)) ?? statuses.startIndex
        #expect(!statuses[joined...].contains(.connecting))
        #expect(statuses.last == .connected(slot: 0))
    }
}

// MARK: - Helpers

/// A host on a free port with short timings, and phones that connect to it.
private final class Rig: Sendable {
    let host: ControllerHost
    let port: UInt16
    let outputs = Recorder<(slot: Int, state: ControllerState?)>()
    let requests = Recorder<ControllerHost.ApprovalRequest>()

    init(autoApprove: Bool = true, approvedPhones: Set<Data> = []) async throws {
        var timing = ControllerHost.Timing()
        timing.pingInterval = .milliseconds(50)
        timing.timeout = .milliseconds(300)
        let approver = Approver()
        host = ControllerHost(service: nil, timing: timing, approvedPhones: approvedPhones) { [requests] request in
            requests.append(request)
            if autoApprove {
                approver.host?.approve(request.identity)
            }
        } output: { [outputs] slot, state in
            outputs.append((slot, state))
        }
        approver.host = host
        port = try await host.start()
    }

    deinit {
        host.stop()
    }

    func phone(identity: SecureChannel.PrivateKey = .init(), name: String = "Phone") -> Phone {
        Phone(port: port, identity: identity, name: name)
    }
}

private final class Approver: @unchecked Sendable {
    weak var host: ControllerHost?
}

private final class Phone: Sendable {
    let identity: SecureChannel.PrivateKey
    let link: ControllerLink
    let statuses = Recorder<ControllerLink.Status>()

    init(port: UInt16, identity: SecureChannel.PrivateKey, name: String) {
        self.identity = identity
        var timing = ControllerLink.Timing()
        timing.helloInterval = .milliseconds(50)
        timing.timeout = .seconds(1)
        link = ControllerLink(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
            identity: identity,
            name: name,
            timing: timing
        ) { [statuses] status in
            statuses.append(status)
        }
        link.connect()
    }

    deinit {
        link.disconnect()
    }

    func waitForStatus(_ status: ControllerLink.Status) async throws {
        try await statuses.wait { $0.last == status }
    }
}

/// Sends and receives hand-made messages, for playing a misbehaving phone.
private final class RawSocket: Sendable {
    private let connection: NWConnection

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        connection.start(queue: .global())
    }

    deinit {
        connection.cancel()
    }

    func send(_ message: Message) {
        connection.send(content: message.encoded(), completion: .idempotent)
    }

    func receive(timeout: Duration = .seconds(2)) async throws -> Message {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce(continuation)
            connection.receiveMessage { data, _, _, error in
                if let data {
                    resumeOnce.resume(returning: data)
                } else {
                    resumeOnce.resume(throwing: error ?? TimedOut())
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) { resumeOnce.resume(throwing: TimedOut()) }
        }
        return try Message(decoding: data)
    }

    /// Says hello until the host welcomes us, like a real phone, and returns the Mac's ephemeral key.
    func handshake(_ hello: Message) async throws -> Data {
        try await welcome(hello).ephemeral
    }

    /// Says hello until the host welcomes us, and returns the welcome.
    func welcome(_ hello: Message) async throws -> (ephemeral: Data, sealed: Data) {
        for _ in 0..<20 {
            send(hello)
            if case .welcome(let macEphemeral, let sealed) = try await receive() {
                return (macEphemeral, sealed)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw TimedOut()
    }
}

/// Collects values from callbacks on any thread, for tests to wait on.
private final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    var snapshot: [Value] { lock.withLock { values } }

    func append(_ value: Value) {
        lock.withLock { values.append(value) }
    }

    func wait(until condition: @escaping @Sendable ([Value]) -> Bool) async throws {
        try await waitUntil { self.lock.withLock { condition(self.values) } }
    }
}

private struct TimedOut: Error {}

private func waitUntil(timeout: Duration = .seconds(5), _ condition: @Sendable () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TimedOut() }
        try await Task.sleep(for: .milliseconds(10))
    }
}
