import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("getDiary fetches and decrypts the diary in its response wrapper")
func getDiaryFetchesDecryptedDiary() async throws {
    let fixture = try diaryFixture()
    let transport = DiaryResponseTransport(statusCode: 200, body: wrapped(fixture))
    let client = await authenticatedClient(transport: transport)

    let diary = try await client.getDiary(id: "diary-1")

    #expect(diary.id == "diary-1")
    #expect(diary.title == "First diary")
    #expect(diary.description == "From Go fixture")
    #expect(diary.version == 1_791_970_000_000)
    #expect(transport.request?.url.path == "/api/v1/diaries/diary-1")
    #expect(transport.request?.method == "GET")
    #expect(transport.request?.headers["Authorization"] == "Bearer session-token")
}

@Test("getDiary preserves a typed HTTP 404 error")
func getDiaryReturnsTypedNotFoundStatus() async throws {
    let responseBody = Data(#"{"error":"not found"}"#.utf8)
    let transport = DiaryResponseTransport(statusCode: 404, body: responseBody)
    let client = await authenticatedClient(transport: transport)

    do {
        _ = try await client.getDiary(id: "missing")
        Issue.record("Expected a typed HTTP status error")
    } catch let error as ThingsDiaryClientError {
        #expect(error == .httpStatus(404, body: responseBody))
    }
}

@Test("diaries sends the next page token as a query parameter")
func diariesRequestsNextPage() async throws {
    let fixtureURL = try #require(Bundle.module.url(
        forResource: "diaries-response",
        withExtension: "json",
        subdirectory: "Fixtures"
    ))
    let transport = DiaryResponseTransport(
        statusCode: 200,
        body: try Data(contentsOf: fixtureURL)
    )
    let client = await authenticatedClient(transport: transport)
    let token = "cursor+/="

    let page = try await client.diaries(nextPageToken: token)

    let queryItems = URLComponents(url: try #require(transport.request?.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(queryItems?.first(where: { $0.name == "next_page_token" })?.value == token)
    #expect(page.items.first?.id == "diary-1")
}

private func authenticatedClient(
    transport: DiaryResponseTransport
) async -> ThingsDiaryClient {
    let authTransport = AuthenticatedDiaryTransport(
        diaryTransport: transport
    )
    let authenticatedClient = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: authTransport
    )
    try! await authenticatedClient.login(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    )
    return authenticatedClient
}

private func diaryFixture() throws -> [String: Any] {
    let url = try #require(Bundle.module.url(
        forResource: "diaries-response",
        withExtension: "json",
        subdirectory: "Fixtures"
    ))
    let data = try Data(contentsOf: url)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let diaries = try #require(json["diaries"] as? [[String: Any]])
    return try #require(diaries.first)
}

private func wrapped(_ diary: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["diary": diary])
}

private final class DiaryResponseTransport: ThingsDiaryTransport, @unchecked Sendable {
    let statusCode: Int
    let body: Data
    private(set) var request: ThingsDiaryHTTPRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        self.request = request
        return ThingsDiaryHTTPResponse(statusCode: statusCode, body: body)
    }
}

private struct AuthenticatedDiaryTransport: ThingsDiaryTransport {
    let diaryTransport: DiaryResponseTransport

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/login":
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"challenge_id":"challenge-1","nonce":"dGhpbmdzZGlhcnkgY29tcGF0aWJpbGl0eSB2ZWN0b3IgdjE=","kdf_salt":"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"}"#.utf8)
            )
        case "/api/v1/auth/login/verify":
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"token":"session-token"}"#.utf8)
            )
        default:
            return try await diaryTransport.send(request)
        }
    }
}
