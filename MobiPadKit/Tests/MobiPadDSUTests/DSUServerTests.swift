import Foundation
import MobiPadProtocol
import Network
import Testing
@testable import MobiPadDSU

/// Talks to a real server over UDP on localhost, the way Dolphin does: one socket lists
/// ports, and every controller gets its own socket that subscribes to one slot.
@Suite(.timeLimit(.minutes(1)))
struct DSUServerTests {
    @Test func servesEachSlotOnlyToItsSubscribers() async throws {
        let server = DSUServer(port: 0)
        let port = try await server.start()
        defer { server.stop() }
        server.update(slot: 1, state: ControllerState(buttons: [.a]))

        let hotplug = UDPClient(port: port)
        try await hotplug.send(ClientRequest.listPorts())
        var connectedSlots: [Int] = []
        for _ in 0..<4 {
            let info = try ServerMessage(await hotplug.receive())
            #expect(info.type == 0x10_0001)
            if info.bytes[21] == 2 { connectedSlots.append(Int(info.bytes[20])) }
        }
        #expect(connectedSlots == [1])

        let player1 = UDPClient(port: port)
        try await player1.send(ClientRequest.subscribe(slot: 1))
        let first = try ServerMessage(await player1.receive())
        #expect(first.bytes[20] == 1)
        #expect(first.bytes[49] == 255) // Cross (A)

        let player2 = UDPClient(port: port)
        try await player2.send(ClientRequest.subscribe(slot: 2))
        // Give the subscription time to land before the next update.
        try await Task.sleep(for: .milliseconds(100))

        server.update(slot: 1, state: ControllerState(buttons: [.b]))
        server.update(slot: 2, state: ControllerState(buttons: [.x]))

        let second = try ServerMessage(await player1.receive())
        #expect(second.bytes[20] == 1)
        #expect(second.bytes[50] == 255) // Circle (B)
        #expect(second.bytes.readLittleEndian(UInt32.self, at: 32) > first.bytes.readLittleEndian(UInt32.self, at: 32))

        // Player 2 must see slot 2's update first, not slot 1's.
        let other = try ServerMessage(await player2.receive())
        #expect(other.bytes[20] == 2)
        #expect(other.bytes[48] == 255) // Square (X)
    }

    @Test func reportsDisconnectedSlots() async throws {
        let server = DSUServer(port: 0)
        let port = try await server.start()
        defer { server.stop() }
        server.update(slot: 0, state: ControllerState())
        server.disconnect(slot: 0)

        let hotplug = UDPClient(port: port)
        try await hotplug.send(ClientRequest.listPorts())
        let info = try ServerMessage(await hotplug.receive())
        #expect(info.bytes[20] == 0)
        #expect(info.bytes[21] == 0)
    }

    @Test func passesRumbleOnForConnectedControllers() async throws {
        let rumbles = RumbleLog()
        let server = DSUServer(port: 0) { slot, intensity in rumbles.append((slot, intensity)) }
        let port = try await server.start()
        defer { server.stop() }
        server.update(slot: 1, state: ControllerState())

        let emulator = UDPClient(port: port)
        try await emulator.send(ClientRequest.motorInfo(slot: 1))
        let motors = try ServerMessage(await emulator.receive())
        #expect(motors.type == 0x11_0001)
        #expect(motors.bytes[20] == 1)
        #expect(motors.bytes[31] == 1)

        try await emulator.send(ClientRequest.motorInfo(slot: 2))
        #expect(try ServerMessage(await emulator.receive()).bytes[31] == 0)

        // Slot 2 has no controller, and there is no second motor.
        try await emulator.send(ClientRequest.rumble(slot: 2, intensity: 255))
        try await emulator.send(ClientRequest.rumble(slot: 1, motor: 1, intensity: 255))
        try await emulator.send(ClientRequest.rumble(slot: 1, intensity: 200))
        try await emulator.send(ClientRequest.rumble(slot: 1, intensity: 0))
        try await Task.sleep(for: .milliseconds(200))
        #expect(rumbles.entries.map(\.slot) == [1, 1])
        #expect(rumbles.entries.map(\.intensity) == [200, 0])
    }
}

private final class RumbleLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [(slot: Int, intensity: UInt8)] = []

    var entries: [(slot: Int, intensity: UInt8)] { lock.withLock { _entries } }

    func append(_ entry: (slot: Int, intensity: UInt8)) {
        lock.withLock { _entries.append(entry) }
    }
}

final class UDPClient: Sendable {
    struct Timeout: Error {}

    private let connection: NWConnection

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        connection.start(queue: DispatchQueue(label: "UDPClient"))
    }

    deinit {
        connection.cancel()
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive(timeout: TimeInterval = 2) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce(continuation)
            connection.receiveMessage { data, _, _, error in
                if let data {
                    resumeOnce.resume(returning: data)
                } else {
                    resumeOnce.resume(throwing: error ?? Timeout())
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce.resume(throwing: Timeout())
            }
        }
    }
}
