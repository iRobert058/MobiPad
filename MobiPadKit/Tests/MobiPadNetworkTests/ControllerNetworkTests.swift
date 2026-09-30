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
        let phone = rig.phone()
        try await phone.waitForStatus(.connected(slot: 0))

        phone.link.send(ControllerState(buttons: [.a]))
        try await rig.outputs.wait { $0.contains { $0.slot == 0 && $0.state?.buttons == [.a] } }
        #expect(rig.host.players().map(\.name) == ["Phone"])
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
        let returning = rig.phone(clientID: second.clientID)
        try await returning.waitForStatus(.connected(slot: 1))
    }

    @Test func measuresLatency() async throws {
        let rig = try await Rig()
        let phone = rig.phone()
        try await phone.waitForStatus(.connected(slot: 0))
        try await waitUntil { rig.host.players().first?.latency != nil }
    }

    @Test func silentPhoneLosesItsSlot() async throws {
        let rig = try await Rig()
        // A raw socket that says hello and then nothing, like a phone that lost Wi-Fi.
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: rig.port)!, using: .udp)
        connection.start(queue: .global())
        defer { connection.cancel() }
        connection.send(content: Message.hello(clientID: UUID(), name: "Gone").encoded(), completion: .idempotent)

        try await waitUntil { rig.host.players().count == 1 }
        try await rig.outputs.wait { $0.contains { $0.slot == 0 && $0.state == nil } }
        #expect(rig.host.players().isEmpty)
    }
}

// MARK: - Helpers

/// A host on a free port with short timings, and phones that connect to it.
private final class Rig: Sendable {
    let host: ControllerHost
    let port: UInt16
    let outputs = Recorder<(slot: Int, state: ControllerState?)>()

    init() async throws {
        var timing = ControllerHost.Timing()
        timing.pingInterval = .milliseconds(50)
        timing.timeout = .milliseconds(300)
        host = ControllerHost(service: nil, timing: timing) { [outputs] slot, state in
            outputs.append((slot, state))
        }
        port = try await host.start()
    }

    deinit {
        host.stop()
    }

    func phone(clientID: UUID = UUID()) -> Phone {
        Phone(port: port, clientID: clientID)
    }
}

private final class Phone: Sendable {
    let clientID: UUID
    let link: ControllerLink
    let statuses = Recorder<ControllerLink.Status>()

    init(port: UInt16, clientID: UUID) {
        self.clientID = clientID
        var timing = ControllerLink.Timing()
        timing.helloInterval = .milliseconds(50)
        timing.timeout = .seconds(1)
        link = ControllerLink(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
            clientID: clientID,
            name: "Phone",
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
