import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("entries sends bearer auth and decodes encrypted entities with pagination")
func entriesListPreservesEncryptedEnvelopeAndPagination() async throws {
    let transport = EntryEndpointTransport()
    let client = try await entryClient(transport: transport)

    let page = try await client.entries(diaryID: "diary-1", nextPageToken: "cursor+/=")

    #expect(page.items.count == 1)
    #expect(page.items[0].id == "entry-1")
    #expect(page.items[0].details.data == Data([1, 2, 3]))
    #expect(page.items[0].topicID == "topic-1")
    #expect(page.nextPageToken == "next-token")
    #expect(transport.requests.last?.url.path == "/api/v1/diaries/diary-1/entries")
    let query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.first(where: { $0.name == "next_page_token" })?.value == "cursor+/=")
    #expect(transport.requests.last?.headers["Authorization"] == "Bearer session-token")
}

@Test("entry get, put, delete, and restore use typed wire envelopes")
func entryLifecycleEndpointsUseExpectedRequests() async throws {
    let transport = EntryEndpointTransport()
    let client = try await entryClient(transport: transport)
    let entity = endpointEntry()

    let fetched = try await client.getEntry(diaryID: "diary-1", entryID: "entry-1")
    #expect(fetched == entity)

    let put = try await client.putEntry(
        diaryID: "diary-1",
        entryID: "entry-1",
        version: 1_791_970_000_000,
        topicID: "topic-1",
        encryption: entity.encryption,
        details: entity.details,
        preview: ThingsDiaryEncryptedPayload(nonce: Data([4]), data: Data([5]))
    )
    #expect(put == entity)
    let putRequest = try #require(transport.requests.last)
    #expect(putRequest.method == "PUT")
    let encodedSignature = try #require(putRequest.headers["X-Signature"])
    let auth = try #require(await client.authentication)
    #expect(try ThingsDiaryCrypto.verify(
        try #require(Data(base64Encoded: encodedSignature)),
        for: putRequest.body,
        publicKey: auth.credentials.signingPublicKey
    ))
    let putBody = try #require(JSONSerialization.jsonObject(with: putRequest.body) as? [String: Any])
    #expect(putBody["version"] as? Int == 1_791_970_000_000)
    #expect(putBody["topic_id"] as? String == "topic-1")
    #expect(putBody["details"] as? [String: String] == ["nonce": "AQ==", "data": "AQID"])

    try await client.deleteEntry(diaryID: "diary-1", entryID: "entry-1", soft: false)
    let deleteQuery = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(transport.requests.last?.method == "DELETE")
    #expect(deleteQuery?.first(where: { $0.name == "soft" })?.value == "false")

    let restored = try await client.restoreEntry(diaryID: "diary-1", entryID: "entry-1")
    #expect(restored == entity)
    #expect(transport.requests.last?.url.path == "/api/v1/diaries/diary-1/entries/entry-1/restore")
    #expect(transport.requests.last?.method == "POST")
}

private func entryClient(transport: EntryEndpointTransport) async throws -> ThingsDiaryClient {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: transport
    )
    _ = try await client.register(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
        kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
    )
    return client
}

private func endpointEntry() -> ThingsDiaryEntry {
    ThingsDiaryEntry(
        id: "entry-1",
        diaryID: "diary-1",
        version: 1_791_970_000_000,
        createdAt: Date(timeIntervalSince1970: 1_791_936_000),
        updatedAt: Date(timeIntervalSince1970: 1_791_936_100),
        deletedAt: nil,
        topicID: "topic-1",
        encryption: ThingsDiaryEntityEncryption(
            diaryKeyID: "key-1",
            encryptedKeyNonce: Data([8]),
            encryptedKeyData: Data([9])
        ),
        details: ThingsDiaryEncryptedPayload(nonce: Data([1]), data: Data([1, 2, 3]))
    )
}

private final class EntryEndpointTransport: ThingsDiaryTransport, @unchecked Sendable {
    private(set) var requests: [ThingsDiaryHTTPRequest] = []

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        requests.append(request)
        switch request.url.path {
        case "/api/v1/auth/register":
            return ThingsDiaryHTTPResponse(statusCode: 201, body: Data(#"{"token":"session-token"}"#.utf8))
        case "/api/v1/diaries/diary-1/entries":
            return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"entries":[{"id":"entry-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","topic_id":"topic-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CA==","encrypted_key_data":"CQ=="},"details":{"nonce":"AQ==","data":"AQID"}}],"next_page_token":"next-token"}"#.utf8))
        case "/api/v1/diaries/diary-1/entries/entry-1":
            if request.method == "DELETE" {
                return ThingsDiaryHTTPResponse(statusCode: 204, body: Data())
            }
            if request.method == "PUT" {
                return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"entry":{"id":"entry-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","topic_id":"topic-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CA==","encrypted_key_data":"CQ=="},"details":{"nonce":"AQ==","data":"AQID"}}}"#.utf8))
            }
            return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"entry":{"id":"entry-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","topic_id":"topic-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CA==","encrypted_key_data":"CQ=="},"details":{"nonce":"AQ==","data":"AQID"}}}"#.utf8))
        case "/api/v1/diaries/diary-1/entries/entry-1/restore":
            return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"entry":{"id":"entry-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","topic_id":"topic-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CA==","encrypted_key_data":"CQ=="},"details":{"nonce":"AQ==","data":"AQID"}}}"#.utf8))
        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }
}
