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
        let host = ControllerHost(service: nil) { slot, state in
            if let state { dsuServer.update(slot: slot, state: state) } else { dsuServer.disconnect(slot: slot) }
        }
        let hostPort = try await host.start()
        defer { host.stop() }

        let link = ControllerLink(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: hostPort)!),
            clientID: UUID(),
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
}
