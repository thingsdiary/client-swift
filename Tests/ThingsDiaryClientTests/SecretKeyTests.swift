import Foundation
import Testing

@testable import ThingsDiaryClient

@Test("TDKV1 key matches the frontend credential vector")
func derivesCredentialsFromTDKV1SecretKey() throws {
  let input = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
  let secretKey = try ThingsDiarySecretKey.parse(input)

  #expect(secretKey.rawValue == input)

  let credentials = try ThingsDiaryCrypto.deriveCredentials(
    secretKey: secretKey.rawValue,
    salt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
  )

  #expect(
    credentials.signingPrivateKey.base64EncodedString()
      == "GN5CK17j89zID8z4/qSDGux6iT3s4HkoPk1quC1mDF4=")
  #expect(
    credentials.signingPublicKey.base64EncodedString()
      == "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")
  #expect(
    credentials.encryptionPrivateKey.base64EncodedString()
      == "X3LAKewxN21hq7S4BIOxGlKlgFqYk8TcBAeDWM61g0o=")
  #expect(
    credentials.encryptionPublicKey.base64EncodedString()
      == "jjGmcQ2pJFhtf/qBjRDYkCNRKplSRrRW8Jr4mGymhFQ=")
}

@Test("TDKV1 input is normalized like the frontend")
func normalizesTDKV1SecretKey() throws {
  let secretKey = try ThingsDiarySecretKey.parse(
    "  tdkvi 000g 40r4 0m30 e209 185g r38e iw6  "
  )

  #expect(secretKey.rawValue == "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6")
}

@Test("TDKV1 rejects a bad checksum")
func rejectsInvalidTDKV1Checksum() {
  #expect(throws: ThingsDiarySecretKeyError.invalidChecksum) {
    try ThingsDiarySecretKey.parse("TDKV1-000G-40R4-0M30-E209-185G-R38E-1W0")
  }
}

@Test("Generated TDKV1 keys are valid canonical keys")
func generatesValidTDKV1SecretKey() throws {
  let generated = ThingsDiarySecretKey.generate()

  #expect(generated.rawValue.count == 39)
  #expect(try ThingsDiarySecretKey.parse(generated.rawValue) == generated)
}
