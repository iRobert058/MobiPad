import CryptoKit
import Foundation
import Testing
import MobiPadProtocol

struct SecureChannelTests {
    let phoneIdentity = SecureChannel.PrivateKey()
    let phoneEphemeral = SecureChannel.PrivateKey()
    let macEphemeral = SecureChannel.PrivateKey()

    func macChannel(phoneIdentity identity: Data? = nil) throws -> SecureChannel {
        try .mac(
            ephemeral: macEphemeral,
            phoneIdentity: identity ?? phoneIdentity.publicKey.rawRepresentation,
            phoneEphemeral: phoneEphemeral.publicKey.rawRepresentation
        )
    }

    func phoneChannel(identity: SecureChannel.PrivateKey? = nil) throws -> SecureChannel {
        try .phone(
            identity: identity ?? phoneIdentity,
            ephemeral: phoneEphemeral,
            macEphemeral: macEphemeral.publicKey.rawRepresentation
        )
    }

    @Test func bothSidesDeriveTheSameKey() throws {
        let message = SessionMessage.state(sequence: 7, ControllerState(buttons: [.b]))
        #expect(try macChannel().open(phoneChannel().seal(message)) == message)
        #expect(try phoneChannel().open(macChannel().seal(.slot(2))) == .slot(2))
    }

    /// Someone who copies an approved phone's public key can't talk to the Mac,
    /// because they don't have the matching private key.
    @Test func impostorWithoutThePrivateKeyIsRejected() throws {
        let impostor = try phoneChannel(identity: SecureChannel.PrivateKey())
        #expect(throws: (any Error).self) { try macChannel().open(impostor.seal(.goodbye)) }
    }

    /// Neither side accepts what it sealed itself, so the Mac's welcome can't be sent back to it.
    @Test func sealedMessagesCantBeReflected() throws {
        let mac = try macChannel()
        let phone = try phoneChannel()
        #expect(throws: (any Error).self) { try mac.open(mac.seal(.slot(0))) }
        #expect(throws: (any Error).self) { try phone.open(phone.seal(.goodbye)) }
    }

    @Test func tamperedMessagesAreRejected() throws {
        var box = try phoneChannel().seal(.goodbye)
        box[box.count - 1] ^= 0x01
        #expect(throws: (any Error).self) { try macChannel().open(box) }
    }

    @Test func everyMessageLooksDifferent() throws {
        let channel = try phoneChannel()
        #expect(channel.seal(.goodbye) != channel.seal(.goodbye))
    }
}
