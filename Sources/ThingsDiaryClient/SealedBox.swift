import Foundation
import _Clibsodium

extension ThingsDiaryCrypto {
  public static func seal(
    _ plaintext: Data,
    recipientPublicKey: Data
  ) throws -> Data {
    guard recipientPublicKey.count == Int(crypto_box_publickeybytes()) else {
      throw ThingsDiaryCryptoError.invalidKeyLength
    }
    guard sodium_init() >= 0 else {
      throw ThingsDiaryCryptoError.initializationFailed
    }

    let overhead = Int(crypto_box_sealbytes())
    var sealedBox = Data(count: plaintext.count + overhead)
    let messageStorage = plaintext.isEmpty ? Data([0]) : plaintext
    let status = sealedBox.withUnsafeMutableBytes { sealedBytes in
      messageStorage.withUnsafeBytes { messageBytes in
        recipientPublicKey.withUnsafeBytes { publicKeyBytes in
          crypto_box_seal(
            sealedBytes.bindMemory(to: UInt8.self).baseAddress!,
            messageBytes.bindMemory(to: UInt8.self).baseAddress!,
            UInt64(plaintext.count),
            publicKeyBytes.bindMemory(to: UInt8.self).baseAddress!
          )
        }
      }
    }

    guard status == 0 else {
      throw ThingsDiaryCryptoError.encryptionFailed
    }
    return sealedBox
  }

  public static func openSealedBox(
    _ sealedBox: Data,
    recipientPrivateKey: Data,
    recipientPublicKey: Data
  ) throws -> Data {
    guard recipientPrivateKey.count == Int(crypto_box_secretkeybytes()),
      recipientPublicKey.count == Int(crypto_box_publickeybytes())
    else {
      throw ThingsDiaryCryptoError.invalidKeyLength
    }

    let overhead = Int(crypto_box_sealbytes())
    guard sealedBox.count >= overhead else {
      throw ThingsDiaryCryptoError.invalidCiphertext
    }
    guard sodium_init() >= 0 else {
      throw ThingsDiaryCryptoError.initializationFailed
    }

    var plaintext = Data(count: sealedBox.count - overhead)
    let status = plaintext.withUnsafeMutableBytes { plaintextBytes in
      sealedBox.withUnsafeBytes { sealedBytes in
        recipientPublicKey.withUnsafeBytes { publicKeyBytes in
          recipientPrivateKey.withUnsafeBytes { privateKeyBytes in
            crypto_box_seal_open(
              plaintextBytes.bindMemory(to: UInt8.self).baseAddress,
              sealedBytes.bindMemory(to: UInt8.self).baseAddress!,
              UInt64(sealedBox.count),
              publicKeyBytes.bindMemory(to: UInt8.self).baseAddress!,
              privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!
            )
          }
        }
      }
    }

    guard status == 0 else {
      throw ThingsDiaryCryptoError.authenticationFailed
    }
    return plaintext
  }
}
