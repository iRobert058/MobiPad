import Foundation
import MobiPadProtocol
import Testing
@testable import MobiPadDSU

/// Byte offsets below follow Dolphin's DualShockUDPProto.h (the client we target).
struct DSUMessagesTests {
    @Test func crc32MatchesZlib() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func messagesHaveTheSizesDolphinExpects() throws {
        let padData = DSU.padData(slot: 0, state: ControllerState(), packetCounter: 1, timestampMicroseconds: 0, serverID: 7)
        #expect(padData.count == 100)
        #expect(DSU.portInfo(slot: 0, isConnected: true, serverID: 7).count == 32)
        #expect(DSU.versionResponse(serverID: 7).count == 24)

        let header = try ServerMessage(padData)
        #expect(header.bytes.readLittleEndian(UInt16.self, at: 4) == 1001)
        #expect(header.bytes.readLittleEndian(UInt16.self, at: 6) == 84) // size minus header
        #expect(header.bytes.readLittleEndian(UInt32.self, at: 12) == 7)
        #expect(header.type == 0x10_0002)
    }

    @Test func neutralStateIsCenteredAndReleased() throws {
        let message = try ServerMessage(DSU.padData(slot: 2, state: ControllerState(), packetCounter: 5, timestampMicroseconds: 0, serverID: 0))
        #expect(message.bytes[20] == 2) // slot
        #expect(message.bytes[21] == 2) // connected
        #expect(message.bytes[31] == 1) // active
        #expect(message.bytes.readLittleEndian(UInt32.self, at: 32) == 5)
        #expect(message.bytes[36...39] == [0, 0, 0, 0])
        #expect(message.bytes[40...43] == [128, 128, 128, 128])
        #expect(message.bytes[44...55].allSatisfy { $0 == 0 })
    }

    @Test func mapsButtonsByPosition() throws {
        let state = ControllerState(
            buttons: [.a, .y, .dpadUp, .menu, .leftShoulder, .home],
            leftTrigger: 0,
            rightTrigger: 200
        )
        let bytes = try ServerMessage(DSU.padData(slot: 0, state: state, packetCounter: 0, timestampMicroseconds: 0, serverID: 0)).bytes
        #expect(bytes[36] == 0x08 | 0x10) // Options, D-pad up
        #expect(bytes[37] == 0x40 | 0x10 | 0x04 | 0x02) // Cross, Triangle, L1, R2
        #expect(bytes[38] == 1) // PS
        #expect(bytes[47] == 255) // D-pad up pressure
        #expect(bytes[49] == 255) // Cross pressure
        #expect(bytes[51] == 255) // Triangle pressure
        #expect(bytes[53] == 255) // L1 pressure
        #expect(bytes[54] == 200) // R2
        #expect(bytes[55] == 0) // L2
    }

    @Test func mapsSticksToBytesWithUpPositive() {
        #expect(DSU.stickByte(0) == 128)
        #expect(DSU.stickByte(32767) == 255)
        #expect(DSU.stickByte(-32767) == 1)
    }

    @Test func disconnectedPortInfoKeepsTheSlotNumber() throws {
        let bytes = try ServerMessage(DSU.portInfo(slot: 3, isConnected: false, serverID: 0)).bytes
        #expect(bytes[20] == 3)
        #expect(bytes[21...31].allSatisfy { $0 == 0 })
    }

    @Test func parsesDolphinRequests() throws {
        #expect(try DSU.Request(decoding: ClientRequest.listPorts()) == .listPorts(slots: [0, 1, 2, 3]))
        #expect(try DSU.Request(decoding: ClientRequest.subscribe(slot: 2)) == .subscribe(slots: [2]))
        #expect(try DSU.Request(decoding: ClientRequest.subscribe(flags: 0)) == .subscribe(slots: [0, 1, 2, 3]))
        #expect(try DSU.Request(decoding: ClientRequest.subscribe(flags: 2, mac: DSU.macAddress(slot: 3))) == .subscribe(slots: [3]))
    }

    @Test func rejectsCorruptRequests() {
        var corrupted = ClientRequest.listPorts()
        corrupted[25] ^= 0xFF
        #expect(throws: DSU.Request.ParseError.self) { try DSU.Request(decoding: corrupted) }

        var fromServer = ClientRequest.listPorts()
        fromServer[3] = UInt8(ascii: "S")
        #expect(throws: DSU.Request.ParseError.self) { try DSU.Request(decoding: fromServer) }
    }
}

/// Builds requests the way Dolphin's DSU client does.
enum ClientRequest {
    static func listPorts() -> Data {
        var payload: [UInt8] = []
        payload.appendLittleEndian(Int32(4))
        payload += [0, 1, 2, 3]
        return DSU.message(.portInfo, payload: payload, serverID: 99, magic: DSU.clientMagic)
    }

    static func subscribe(slot: UInt8 = 0, flags: UInt8 = 1, mac: [UInt8] = [0, 0, 0, 0, 0, 0]) -> Data {
        DSU.message(.padData, payload: [flags, slot] + mac, serverID: 99, magic: DSU.clientMagic)
    }
}

/// A server message whose header and checksum have been validated.
struct ServerMessage {
    let bytes: [UInt8]
    var type: UInt32 { bytes.readLittleEndian(UInt32.self, at: 16) }

    struct Invalid: Error {}

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == DSU.serverMagic,
              Int(bytes.readLittleEndian(UInt16.self, at: 6)) + DSU.headerSize == bytes.count
        else { throw Invalid() }
        var unsigned = bytes
        unsigned.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        guard CRC32.checksum(unsigned) == bytes.readLittleEndian(UInt32.self, at: 8) else { throw Invalid() }
    }
}
