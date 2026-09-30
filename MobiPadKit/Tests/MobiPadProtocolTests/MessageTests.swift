import Foundation
import Testing
@testable import MobiPadProtocol

struct MessageTests {
    static let busyState = ControllerState(
        buttons: [.a, .menu, .dpadLeft],
        leftStick: .init(x: -32767, y: 1234),
        rightStick: .init(x: 32767, y: -1),
        leftTrigger: 255,
        rightTrigger: 7
    )

    static let allMessages: [Message] = [
        .state(sequence: 0xDEAD_BEEF, busyState),
        .hello(clientID: UUID(), name: "Player’s iPhone 📱"),
        .welcome(slot: 3),
        .full,
        .goodbye,
        .ping(token: .max),
        .pong(token: 42),
    ]

    @Test(arguments: allMessages)
    func roundTrips(message: Message) throws {
        #expect(try Message(decoding: message.encoded()) == message)
    }

    @Test func stateUsesDocumentedLayout() {
        let bytes = [UInt8](Message.state(sequence: 1, Self.busyState).encoded())
        #expect(bytes.count == 20)
        #expect(bytes[0..<4] == [0x4D, 0x50, 1, 1])
        #expect(bytes[4..<8] == [0, 0, 0, 1])
        #expect(bytes[8..<10] == [0x21, 0x01]) // a | menu | dpadLeft
        #expect(bytes[10..<12] == [0x80, 0x01]) // -32767
        #expect(bytes[18..<20] == [255, 7])
    }

    @Test func truncatesLongNames() throws {
        let long = String(repeating: "x", count: 100)
        let decoded = try Message(decoding: Message.hello(clientID: UUID(), name: long).encoded())
        guard case .hello(_, let name) = decoded else { Issue.record("not a hello"); return }
        #expect(name.count == Message.maxNameLength)
    }

    @Test func rejectsMalformedData() {
        let state = Message.state(sequence: 1, ControllerState()).encoded()
        #expect(throws: Message.ParseError.wrongLength) { try Message(decoding: state.dropLast()) }
        #expect(throws: Message.ParseError.tooShort) { try Message(decoding: Data([0x4D])) }
        #expect(throws: Message.ParseError.badMagic) { try Message(decoding: Data([0, 0, 1, 1])) }
        #expect(throws: Message.ParseError.unsupportedVersion(9)) { try Message(decoding: Data([0x4D, 0x50, 9, 1])) }
        #expect(throws: Message.ParseError.unknownMessageType(99)) { try Message(decoding: Data([0x4D, 0x50, 1, 99])) }
    }

    @Test(arguments: [
        (UInt32(2), UInt32(1), true),
        (1, 2, false),
        (5, 5, false),
        (0, .max, true), // wrapped around
        (.max, 0, false),
    ])
    func ordersSequenceNumbers(sequence: UInt32, other: UInt32, expected: Bool) {
        #expect(Message.isSequence(sequence, newerThan: other) == expected)
    }

    @Test func quantizesNormalizedStickInput() {
        #expect(ControllerState.Stick(normalizedX: 1, normalizedY: -1) == .init(x: 32767, y: -32767))
        #expect(ControllerState.Stick(normalizedX: 5, normalizedY: .nan) == .init(x: 32767, y: 0))
        #expect(ControllerState.Stick(x: .min, y: 0).x == -32767)
    }
}
