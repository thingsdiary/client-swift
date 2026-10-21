import Foundation
import Testing

@testable import ThingsDiaryClient

@Test("Register derives credentials and sends their public keys")
func registerDerivesCredentialsAndReturnsAuthState() async throws {
  let transport = RegisterTransport()
  let client = ThingsDiaryClient(
    baseURL: URL(string: "https://example.test/api")!,
    transport: transport
  )

  let state = try await client.register(
    login: "person@example.test",
    password: "secret",
    secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
    kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
  )

  #expect(state.token == "registered-token")
  #expect(
    state.credentials.signingPublicKey.base64EncodedString()
      == "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")
}

private struct RegisterTransport: ThingsDiaryTransport {
  func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
    #expect(request.url.path == "/api/v1/auth/register")
    #expect(request.method == "POST")
    #expect(request.headers["Content-Type"] == "application/json")
    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: String])
    #expect(body["login"] == "person@example.test")
    #expect(body["password"] == "secret")
    #expect(body["kdf_salt"] == "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
    #expect(body["encryption_public_key"] == "jjGmcQ2pJFhtf/qBjRDYkCNRKplSRrRW8Jr4mGymhFQ=")
    #expect(body["signature_public_key"] == "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")
    #expect(body["signing_public_key"] == nil)
    return ThingsDiaryHTTPResponse(
      statusCode: 201,
      body: Data(#"{"token":"registered-token"}"#.utf8)
    )
  }
}
