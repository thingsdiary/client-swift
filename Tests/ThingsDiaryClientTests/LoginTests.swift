import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("Login signs the server challenge and returns reusable auth state")
func loginReturnsAuthState() async throws {
    let transport = LoginTransport()
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: transport
    )

    let state = try await client.login(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    )

    #expect(state.token == "session-token")
    #expect(state.credentials.signingPublicKey.base64EncodedString()
        == "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")
}

@Test("Authenticated client returns decrypted diaries")
func listsDecryptedDiaries() async throws {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: LoginTransport()
    )
    try await client.login(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    )

    let page = try await client.diaries()

    #expect(page.items.count == 1)
    #expect(page.items.first?.id == "diary-1")
    #expect(page.items.first?.title == "First diary")
    #expect(page.items.first?.description == "From Go fixture")
    #expect(page.items.first?.version == 1_791_970_000_000)
    #expect(page.nextPageToken == nil)
}

private struct LoginTransport: ThingsDiaryTransport {
    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/login":
            let body = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
            #expect(request.method == "POST")
            #expect(body?["login"] == "person@example.test")
            #expect(body?["password"] == "secret")
            return response(
                """
                {
                  "challenge_id": "challenge-1",
                  "nonce": "dGhpbmdzZGlhcnkgY29tcGF0aWJpbGl0eSB2ZWN0b3IgdjE=",
                  "kdf_salt": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
                }
                """
            )

        case "/api/v1/auth/login/verify":
            let body = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
            let signature = try #require(body?["signed_nonce"].flatMap { Data(base64Encoded: $0) })
            let message = Data("thingsdiary compatibility vector v1".utf8)
            let publicKey = Data(base64Encoded: "Y80ZyPYy06Gmm5Jfm2mGYHC4Ho/2HDqOliSGIVM/eQE=")!
            #expect(body?["challenge_id"] == "challenge-1")
            #expect(try ThingsDiaryCrypto.verify(signature, for: message, publicKey: publicKey))
            return response(#"{"token":"session-token"}"#)

        case "/api/v1/diaries":
            #expect(request.method == "GET")
            #expect(request.headers["Authorization"] == "Bearer session-token")
            let url = try #require(Bundle.module.url(
                forResource: "diaries-response",
                withExtension: "json",
                subdirectory: "Fixtures"
            ))
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: try Data(contentsOf: url)
            )

        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }

    private func response(_ json: String) -> ThingsDiaryHTTPResponse {
        ThingsDiaryHTTPResponse(statusCode: 200, body: Data(json.utf8))
    }
}

