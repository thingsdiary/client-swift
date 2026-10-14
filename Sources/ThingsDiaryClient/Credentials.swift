import CommonCrypto
import CryptoKit
import Foundation

public struct ThingsDiaryCredentials: Sendable, Equatable {
    public let encryptionPrivateKey: Data
    public let encryptionPublicKey: Data
    public let signingPrivateKey: Data
    public let signingPublicKey: Data

    public init(
        encryptionPrivateKey: Data,
        encryptionPublicKey: Data,
        signingPrivateKey: Data,
        signingPublicKey: Data
    ) {
        self.encryptionPrivateKey = encryptionPrivateKey
        self.encryptionPublicKey = encryptionPublicKey
        self.signingPrivateKey = signingPrivateKey
        self.signingPublicKey = signingPublicKey
    }
}

public struct ThingsDiaryEncryptedData: Sendable, Equatable {
    public let nonce: Data
    public let ciphertext: Data

    public init(nonce: Data, ciphertext: Data) {
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}

public enum ThingsDiaryCrypto {
    private static let iterations: UInt32 = 650_000
    private static let keyLength = 32

    public static func deriveCredentials(
        secretKey: String,
        salt: String
    ) throws -> ThingsDiaryCredentials {
        let canonicalSecretKey = try ThingsDiarySecretKey.parse(secretKey)
        let masterSeed = try pbkdf2(
            password: Data(canonicalSecretKey.rawValue.utf8),
            salt: Data(salt.utf8)
        )
        let signingSeed = hkdf(
            input: masterSeed,
            info: Data("thingsdiary-ed25519-v1".utf8)
        )
        let encryptionSeed = hkdf(
            input: masterSeed,
            info: Data("thingsdiary-x25519-v1".utf8)
        )

        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: signingSeed
        )
        let encryptionKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: encryptionSeed
        )

        return ThingsDiaryCredentials(
            encryptionPrivateKey: encryptionSeed,
            encryptionPublicKey: encryptionKey.publicKey.rawRepresentation,
            signingPrivateKey: signingSeed,
            signingPublicKey: signingKey.publicKey.rawRepresentation
        )
    }

    public static func sign(_ message: Data, privateKey: Data) throws -> Data {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return try key.signature(for: message)
    }

    public static func verify(
        _ signature: Data,
        for message: Data,
        publicKey: Data
    ) throws -> Bool {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        return key.isValidSignature(signature, for: message)
    }

    public static func encrypt(
        _ plaintext: Data,
        key: Data,
        nonce: Data? = nil
    ) throws -> ThingsDiaryEncryptedData {
        guard key.count == keyLength else {
            throw ThingsDiaryCryptoError.invalidKeyLength
        }
        let aesNonce: AES.GCM.Nonce
        if let nonce {
            guard nonce.count == 12 else {
                throw ThingsDiaryCryptoError.invalidNonceLength
            }
            aesNonce = try AES.GCM.Nonce(data: nonce)
        } else {
            aesNonce = AES.GCM.Nonce()
        }

        let box = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: aesNonce
        )
        return ThingsDiaryEncryptedData(
            nonce: Data(box.nonce),
            ciphertext: box.ciphertext + box.tag
        )
    }

    public static func decrypt(
        _ ciphertext: Data,
        key: Data,
        nonce: Data
    ) throws -> Data {
        guard key.count == keyLength else {
            throw ThingsDiaryCryptoError.invalidKeyLength
        }
        guard nonce.count == 12 else {
            throw ThingsDiaryCryptoError.invalidNonceLength
        }
        guard ciphertext.count >= 16 else {
            throw ThingsDiaryCryptoError.invalidCiphertext
        }

        let tagStart = ciphertext.index(ciphertext.endIndex, offsetBy: -16)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext[..<tagStart],
            tag: ciphertext[tagStart...]
        )
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    private static func pbkdf2(password: Data, salt: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: keyLength)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &output,
                    output.count
                )
            }
        }

        guard status == kCCSuccess else {
            throw ThingsDiaryCryptoError.keyDerivationFailed(status: status)
        }
        return Data(output)
    }

    private static func hkdf(input: Data, info: Data) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: input),
            salt: Data(),
            info: info,
            outputByteCount: keyLength
        )
        return key.withUnsafeBytes { Data($0) }
    }
}

public enum ThingsDiaryCryptoError: Error, Sendable, Equatable {
    case keyDerivationFailed(status: Int32)
    case invalidKeyLength
    case invalidNonceLength
    case invalidCiphertext
    case initializationFailed
    case authenticationFailed
    case encryptionFailed
}

