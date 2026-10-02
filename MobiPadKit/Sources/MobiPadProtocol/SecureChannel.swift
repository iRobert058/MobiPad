import CryptoKit
import Foundation

/// Encrypts and authenticates everything after the handshake (NFR-06).
///
/// Every phone has a long-term identity key, which the user approves once on the Mac
/// (trust on first use). Every connection also uses fresh ephemeral keys on both sides.
/// The session key mixes two key agreements:
///
/// - phone ephemeral × Mac ephemeral, so every connection gets a new key;
/// - phone identity × Mac ephemeral, which only the owner of the approved identity key can compute.
///
/// So a device that copies an approved phone's public key still can't send input. Each direction has
/// its own key, so a side can't open what it sealed itself: otherwise such a device could send the
/// Mac's welcome back to it as proof that it owns the phone's key. The phone doesn't verify the Mac;
/// the worst a fake Mac can do is read controller input.
public struct SecureChannel: Sendable {
    public typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
    public typealias PublicKey = Curve25519.KeyAgreement.PublicKey

    private let sealingKey: SymmetricKey
    private let openingKey: SymmetricKey

    public struct Failure: Error {}

    /// The phone's side, once it knows the Mac's ephemeral key from the welcome message.
    public static func phone(identity: PrivateKey, ephemeral: PrivateKey, macEphemeral: Data) throws -> SecureChannel {
        let macEphemeralKey = try PublicKey(rawRepresentation: macEphemeral)
        return try SecureChannel(
            ephemeralSecret: ephemeral.sharedSecretFromKeyAgreement(with: macEphemeralKey),
            identitySecret: identity.sharedSecretFromKeyAgreement(with: macEphemeralKey),
            phoneEphemeral: ephemeral.publicKey.rawRepresentation,
            macEphemeral: macEphemeral,
            isPhone: true
        )
    }

    /// The Mac's side, when it answers an approved phone's hello.
    public static func mac(ephemeral: PrivateKey, phoneIdentity: Data, phoneEphemeral: Data) throws -> SecureChannel {
        try SecureChannel(
            ephemeralSecret: ephemeral.sharedSecretFromKeyAgreement(with: PublicKey(rawRepresentation: phoneEphemeral)),
            identitySecret: ephemeral.sharedSecretFromKeyAgreement(with: PublicKey(rawRepresentation: phoneIdentity)),
            phoneEphemeral: phoneEphemeral,
            macEphemeral: ephemeral.publicKey.rawRepresentation,
            isPhone: false
        )
    }

    private init(ephemeralSecret: SharedSecret, identitySecret: SharedSecret, phoneEphemeral: Data, macEphemeral: Data, isPhone: Bool) {
        var keyMaterial = Data()
        ephemeralSecret.withUnsafeBytes { keyMaterial.append(contentsOf: $0) }
        identitySecret.withUnsafeBytes { keyMaterial.append(contentsOf: $0) }
        func key(_ direction: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: keyMaterial),
                salt: phoneEphemeral + macEphemeral,
                info: Data("MobiPad session v2, \(direction)".utf8),
                outputByteCount: 32
            )
        }
        let phoneToMac = key("phone to Mac")
        let macToPhone = key("Mac to phone")
        (sealingKey, openingKey) = isPhone ? (phoneToMac, macToPhone) : (macToPhone, phoneToMac)
    }

    public func seal(_ message: SessionMessage) -> Data {
        // Sealing with a valid key and a random nonce can't fail.
        try! ChaChaPoly.seal(message.encoded(), using: sealingKey).combined
    }

    public func open(_ data: Data) throws -> SessionMessage {
        let plaintext = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: openingKey)
        return try SessionMessage(decoding: plaintext)
    }
}
