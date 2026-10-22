import Foundation
import Testing

@testable import ThingsDiaryClient

@Test("Login signs the server challenge and returns reusable auth state")
func loginReturnsAuthState() async throws {
  let client = ThingsDiaryClient(
    baseURL: URL(string: "https://example.test/api")!,
    transport: LoginTransport()
  )

  let state = try await client.login(
    login: "person@example.test",
    password: "secret",
    secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
  )

  #expect(state.token == "session-token")
  #expect(
    state.credentials.signingPublicKey.base64EncodedString()
      == "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")
}

private struct LoginTransport: ThingsDiaryTransport {
  func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
    switch request.url.path {
    case "/api/v1/auth/login":
      let body = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
      #expect(body?["login"] == "person@example.test")
      return response(
        #"{"challenge_id":"challenge-1","nonce":"dGhpbmdzZGlhcnkgY29tcGF0aWJpbGl0eSB2ZWN0b3IgdjE=","kdf_salt":"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"}"#
      )
    case "/api/v1/auth/login/verify":
      let body = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
      let signature = try #require(body?["signed_nonce"].flatMap { Data(base64Encoded: $0) })
      let publicKey = Data(base64Encoded: "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")!
      #expect(
        try ThingsDiaryCrypto.verify(
          signature,
          for: Data("thingsdiary compatibility vector v1".utf8),
          publicKey: publicKey
        ))
      return response(#"{"token":"session-token"}"#)
    default:
      Issue.record("Unexpected request: \(request.url)")
      return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
    }
  }

  private func response(_ json: String) -> ThingsDiaryHTTPResponse {
    ThingsDiaryHTTPResponse(statusCode: 200, body: Data(json.utf8))
  }
}
