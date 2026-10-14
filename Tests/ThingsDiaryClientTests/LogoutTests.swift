import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("Logout clears auth state after a 204 response")
func logoutClearsAuthStateAfterNoContent() async throws {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: LogoutTransport()
    )
    _ = try await client.register(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
        kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
    )

    try await client.logout()

    do {
        try await client.logout()
        Issue.record("Expected logout without auth state to fail")
    } catch let error as ThingsDiaryClientError {
        #expect(error == .notAuthenticated)
    }
}

@Test("Logout keeps auth state when the server does not return 204")
func logoutKeepsAuthStateAfterFailure() async throws {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: LogoutRetryTransport()
    )
    _ = try await client.register(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
        kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
    )

    do {
        try await client.logout()
        Issue.record("Expected a server error")
    } catch let error as ThingsDiaryClientError {
        #expect(error == .httpStatus(503, body: Data("unavailable".utf8)))
    }
    try await client.logout()
}

private struct LogoutTransport: ThingsDiaryTransport {
    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/register":
            return ThingsDiaryHTTPResponse(
                statusCode: 201,
                body: Data(#"{"token":"session-token"}"#.utf8)
            )
        case "/api/v1/auth/logout":
            #expect(request.method == "POST")
            #expect(request.headers["Authorization"] == "Bearer session-token")
            return ThingsDiaryHTTPResponse(statusCode: 204, body: Data())
        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }
}

private actor LogoutRetryTransport: ThingsDiaryTransport {
    private var logoutCount = 0

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/register":
            return ThingsDiaryHTTPResponse(
                statusCode: 201,
                body: Data(#"{"token":"session-token"}"#.utf8)
            )
        case "/api/v1/auth/logout":
            #expect(request.method == "POST")
            #expect(request.headers["Authorization"] == "Bearer session-token")
            logoutCount += 1
            if logoutCount == 1 {
                return ThingsDiaryHTTPResponse(
                    statusCode: 503,
                    body: Data("unavailable".utf8)
                )
            }
            return ThingsDiaryHTTPResponse(statusCode: 204, body: Data())
        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }
}
