import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("Go and JavaScript derive the same credentials")
func derivesCompatibleCredentials() throws {
    let vector = try CompatibilityVector.load()

    let credentials = try ThingsDiaryCrypto.deriveCredentials(
        secretKey: vector.secretKey,
        salt: vector.salt
    )
    let encryptionPrivateKey = try Data(base64Encoded: vector.encryptionPrivateKey).required()
    let encryptionPublicKey = try Data(base64Encoded: vector.encryptionPublicKey).required()
    let signingPrivateKey = try Data(base64Encoded: vector.signingSeed).required()
    let signingPublicKey = try Data(base64Encoded: vector.signingPublicKey).required()

    #expect(credentials.encryptionPrivateKey == encryptionPrivateKey)
    #expect(credentials.encryptionPublicKey == encryptionPublicKey)
    #expect(credentials.signingPrivateKey == signingPrivateKey)
    #expect(credentials.signingPublicKey == signingPublicKey)
}

private struct CompatibilityVector: Decodable {
    let secretKey: String
    let salt: String
    let encryptionPrivateKey: String
    let encryptionPublicKey: String
    let signingSeed: String
    let signingPublicKey: String
    let message: String
    let signature: String
    let aesKey: String
    let aesNonce: String
    let aesCiphertextAndTag: String
    let sealedBox: String

    enum CodingKeys: String, CodingKey {
        case secretKey = "secret_key"
        case salt
        case encryptionPrivateKey = "encryption_private_key"
        case encryptionPublicKey = "encryption_public_key"
        case signingSeed = "signing_seed"
        case signingPublicKey = "signing_public_key"
        case message, signature
        case aesKey = "aes_key"
        case aesNonce = "aes_nonce"
        case aesCiphertextAndTag = "aes_ciphertext_and_tag"
        case sealedBox = "sealed_box"
    }

    static func load() throws -> Self {
        let url = try #require(Bundle.module.url(
            forResource: "compatibility-vector-v1",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

@Test("Swift opens a Go and JavaScript compatible sealed box")
func opensCompatibleSealedBox() throws {
    let vector = try CompatibilityVector.load()
    let message = try Data(base64Encoded: vector.message).required()
    let sealedBox = try Data(base64Encoded: vector.sealedBox).required()
    let privateKey = try Data(base64Encoded: vector.encryptionPrivateKey).required()
    let publicKey = try Data(base64Encoded: vector.encryptionPublicKey).required()

    let plaintext = try ThingsDiaryCrypto.openSealedBox(
        sealedBox,
        recipientPrivateKey: privateKey,
        recipientPublicKey: publicKey
    )

    #expect(plaintext == message)
}

@Test("Swift sealed boxes use the expected overhead and round trip")
func createsCompatibleSealedBox() throws {
    let vector = try CompatibilityVector.load()
    let message = try Data(base64Encoded: vector.message).required()
    let privateKey = try Data(base64Encoded: vector.encryptionPrivateKey).required()
    let publicKey = try Data(base64Encoded: vector.encryptionPublicKey).required()

    let sealedBox = try ThingsDiaryCrypto.seal(message, recipientPublicKey: publicKey)

    #expect(sealedBox.count == message.count + 48)
    #expect(try ThingsDiaryCrypto.openSealedBox(
        sealedBox,
        recipientPrivateKey: privateKey,
        recipientPublicKey: publicKey
    ) == message)
}

@Test("Swift AES-GCM matches the Go wire format")
func encryptsCompatibleAESGCM() throws {
    let vector = try CompatibilityVector.load()
    let message = try Data(base64Encoded: vector.message).required()
    let key = try Data(base64Encoded: vector.aesKey).required()
    let nonce = try Data(base64Encoded: vector.aesNonce).required()
    let expectedCiphertext = try Data(base64Encoded: vector.aesCiphertextAndTag).required()

    let box = try ThingsDiaryCrypto.encrypt(message, key: key, nonce: nonce)

    #expect(box.nonce == nonce)
    #expect(box.ciphertext == expectedCiphertext)
    #expect(try ThingsDiaryCrypto.decrypt(box.ciphertext, key: key, nonce: box.nonce) == message)
}

@Test("Swift and Go or JavaScript accept each other's Ed25519 signatures")
func signsCompatibleMessage() throws {
    let vector = try CompatibilityVector.load()
    let message = try Data(base64Encoded: vector.message).required()
    let privateKey = try Data(base64Encoded: vector.signingSeed).required()
    let publicKey = try Data(base64Encoded: vector.signingPublicKey).required()
    let expectedSignature = try Data(base64Encoded: vector.signature).required()

    let signature = try ThingsDiaryCrypto.sign(message, privateKey: privateKey)

    #expect(try ThingsDiaryCrypto.verify(expectedSignature, for: message, publicKey: publicKey))
    #expect(try ThingsDiaryCrypto.verify(signature, for: message, publicKey: publicKey))
}

private extension Optional {
    func required() throws -> Wrapped {
        try #require(self)
    }
}

