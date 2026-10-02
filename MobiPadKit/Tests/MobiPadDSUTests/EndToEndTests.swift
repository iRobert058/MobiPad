import Foundation
import MobiPadNetwork
import MobiPadProtocol
import Network
import Testing
@testable import MobiPadDSU

/// Phone → ControllerHost → DSUServer → emulator, wired the way the Mac companion app wires them.
@Suite(.timeLimit(.minutes(1)))
struct EndToEndTests {
    @Test func buttonOnPhoneReachesEmulator() async throws {
        let dsuServer = DSUServer(port: 0)
        let dsuPort = try await dsuServer.start()
        defer { dsuServer.stop() }
        let identity = SecureChannel.PrivateKey()
        let host = ControllerHost(service: nil, approvedPhones: [identity.publicKey.rawRepresentation]) { _ in
        } output: { slot, state in
            if let state { dsuServer.update(slot: slot, state: state) } else { dsuServer.disconnect(slot: slot) }
        }
        let hostPort = try await host.start()
        defer { host.stop() }

        let link = ControllerLink(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: hostPort)!),
            identity: identity,
            name: "Phone"
        ) { _ in }
        link.connect()
        defer { link.disconnect() }

        // The emulator subscribes to slot 0, then the phone presses A.
        let emulator = UDPClient(port: dsuPort)
        try await emulator.send(ClientRequest.subscribe(slot: 0))
        while host.players().isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        link.send(ControllerState(buttons: [.a], leftStick: .init(normalizedX: 1, normalizedY: 0)))

        // The link also resends the neutral state, so skip ahead to the first message with A held.
        var message = try ServerMessage(await emulator.receive())
        while message.bytes[49] != 255 {
            message = try ServerMessage(await emulator.receive())
        }
        #expect(message.bytes[20] == 0) // slot
        #expect(message.bytes[40] == 255) // left stick fully right
    }

    /// Tilt from the phone (Wii Remote layout) reaches the emulator as DSU motion.
    @Test func tiltOnPhoneReachesEmulator() async throws {
        let dsuServer = DSUServer(port: 0)
        let dsuPort = try await dsuServer.start()
        defer { dsuServer.stop() }
        let identity = SecureChannel.PrivateKey()
        let host = ControllerHost(service: nil, approvedPhones: [identity.publicKey.rawRepresentation]) { _ in
        } output: { slot, state in
            if let state { dsuServer.update(slot: slot, state: state) } else { dsuServer.disconnect(slot: slot) }
        }
        let hostPort = try await host.start()
        defer { host.stop() }

        let link = ControllerLink(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: hostPort)!),
            identity: identity,
            name: "Phone"
        ) { _ in }
        link.connect()
        defer { link.disconnect() }

        let emulator = UDPClient(port: dsuPort)
        try await emulator.send(ClientRequest.subscribe(slot: 0))
        while host.players().isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        // Lying face up, turning its nose up.
        link.send(ControllerState(motion: .init(acceleration: .init(x: 0, y: 0, z: 1), rotationRate: .init(x: 45, y: 0, z: 0))))

        var motion = try DolphinMotion(ServerMessage(await emulator.receive()))
        while motion.up == 0 {
            motion = try DolphinMotion(ServerMessage(await emulator.receive()))
        }
        #expect(motion.up == 1)
        #expect(motion.pitchUp == 45)
    }
}
