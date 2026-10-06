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

    static let tiltState = ControllerState(
        buttons: [.b],
        motion: .init(
            acceleration: .init(x: 0.5, y: -1, z: 0.25),
            rotationRate: .init(x: 180, y: -90.5, z: 0)
        )
    )

    static let key = Data(repeating: 0xAB, count: 32)

    static let messages: [Message] = [
        .hello(identity: key, ephemeral: Data(repeating: 0xCD, count: 32), name: "Player’s iPhone 📱"),
        .pending,
        .denied,
        .full,
        .welcome(ephemeral: key, sealed: Data([1, 2, 3])),
        .sealed(Data([4, 5, 6])),
    ]

    static let sessionMessages: [SessionMessage] = [
        .state(sequence: 0xDEAD_BEEF, busyState),
        .state(sequence: 7, tiltState),
        .goodbye,
        .ping(token: .max),
        .pong(token: 42),
        .slot(3),
        .rumble(sequence: 0xFFFF_FFFF, intensity: 200),
    ]

    @Test(arguments: messages)
    func messagesRoundTrip(message: Message) throws {
        #expect(try Message(decoding: message.encoded()) == message)
    }

    @Test(arguments: sessionMessages)
    func sessionMessagesRoundTrip(message: SessionMessage) throws {
        #expect(try SessionMessage(decoding: message.encoded()) == message)
    }

    @Test func helloUsesDocumentedLayout() {
        let bytes = [UInt8](Message.hello(identity: Self.key, ephemeral: Self.key, name: "Ana").encoded())
        #expect(bytes[0..<4] == [0x4D, 0x50, 3, 1])
        #expect(bytes.count == 4 + 64 + 3)
        #expect(Array(bytes[68...]) == Array("Ana".utf8))
    }

    @Test func stateUsesDocumentedLayout() {
        let bytes = [UInt8](SessionMessage.state(sequence: 1, Self.busyState).encoded())
        #expect(bytes.count == 17)
        #expect(bytes[0] == 1)
        #expect(bytes[1..<5] == [0, 0, 0, 1])
        #expect(bytes[5..<7] == [0x21, 0x01]) // a | menu | dpadLeft
        #expect(bytes[7..<9] == [0x80, 0x01]) // -32767
        #expect(bytes[15..<17] == [255, 7])
    }

    @Test func motionFollowsTheStateAsBigEndianFloats() {
        let bytes = [UInt8](SessionMessage.state(sequence: 1, Self.tiltState).encoded())
        #expect(bytes.count == 1 + 16 + 24)
        #expect(bytes[17..<21] == [0x3F, 0x00, 0x00, 0x00]) // acceleration x = 0.5
        #expect(bytes[21..<25] == [0xBF, 0x80, 0x00, 0x00]) // acceleration y = -1
        #expect(bytes[29..<33] == [0x43, 0x34, 0x00, 0x00]) // rotation x = 180
    }

    /// Phones without tilt, including ones built before motion existed, send no motion block.
    @Test func stateWithoutMotionDecodesWithoutMotion() throws {
        let decoded = try SessionMessage(decoding: SessionMessage.state(sequence: 1, Self.busyState).encoded())
        guard case .state(_, let state) = decoded else { Issue.record("not a state"); return }
        #expect(state.motion == nil)
    }

    @Test func rejectsAPartialMotionBlock() {
        let full = SessionMessage.state(sequence: 1, Self.tiltState).encoded()
        #expect(throws: Message.ParseError.wrongLength) { try SessionMessage(decoding: full.dropLast(12)) }
        #expect(throws: Message.ParseError.wrongLength) { try SessionMessage(decoding: full + [0]) }
    }

    @Test func truncatesLongNames() throws {
        let long = String(repeating: "x", count: 100)
        let decoded = try Message(decoding: Message.hello(identity: Self.key, ephemeral: Self.key, name: long).encoded())
        guard case .hello(_, _, let name) = decoded else { Issue.record("not a hello"); return }
        #expect(name.count == Message.maxNameLength)
    }

    @Test func rejectsMalformedData() {
        let hello = Message.hello(identity: Self.key, ephemeral: Self.key, name: "").encoded()
        #expect(throws: Message.ParseError.wrongLength) { try Message(decoding: hello.dropLast()) }
        #expect(throws: Message.ParseError.tooShort) { try Message(decoding: Data([0x4D])) }
        #expect(throws: Message.ParseError.badMagic) { try Message(decoding: Data([0, 0, 2, 2])) }
        #expect(throws: Message.ParseError.unsupportedVersion(2)) { try Message(decoding: Data([0x4D, 0x50, 2, 2])) }
        #expect(throws: Message.ParseError.unknownMessageType(99)) { try Message(decoding: Data([0x4D, 0x50, 3, 99])) }
        #expect(throws: Message.ParseError.wrongLength) { try SessionMessage(decoding: Data([1, 0, 0])) }
    }

    @Test(arguments: [
        (UInt32(2), UInt32(1), true),
        (1, 2, false),
        (5, 5, false),
        (0, .max, true), // wrapped around
        (.max, 0, false),
    ])
    func ordersSequenceNumbers(sequence: UInt32, other: UInt32, expected: Bool) {
        #expect(SessionMessage.isSequence(sequence, newerThan: other) == expected)
    }

    @Test func quantizesNormalizedStickInput() {
        #expect(ControllerState.Stick(normalizedX: 1, normalizedY: -1) == .init(x: 32767, y: -32767))
        #expect(ControllerState.Stick(normalizedX: 5, normalizedY: .nan) == .init(x: 32767, y: 0))
        #expect(ControllerState.Stick(x: .min, y: 0).x == -32767)
    }
}
