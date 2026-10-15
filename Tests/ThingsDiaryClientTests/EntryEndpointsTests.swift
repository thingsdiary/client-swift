import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("entries decrypts JS-compatible content and flags")
func entriesListReturnsPlaintext() async throws {
    let client = try await entryClient(transport: PlaintextEntryTransport())

    let page = try await client.entries(diaryID: "diary-1")

    #expect(page.items.count == 1)
    #expect(page.items[0].content == "Hello from encrypted entry")
    #expect(page.items[0].bookmarked)
    #expect(!page.items[0].archived)
    #expect(!page.items[0].previewHidden)
    #expect(page.items[0].topicID == "topic-1")
    #expect(page.nextPageToken == "next-token")
}

@Test("allEntries loads every plaintext entry page")
func loadsAllPlaintextEntries() async throws {
    let client = try await entryClient(transport: PlaintextEntryTransport())

    let entries = try await client.allEntries(diaryID: "diary-1")

    #expect(entries.map(\.id) == ["entry-1", "entry-2"])
}

@Test("createEntry encrypts plaintext and returns the created entry")
func createsPlaintextEntry() async throws {
    let transport = PutPlaintextEntryTransport()
    let client = try await entryClient(transport: transport)

    let entry = try await client.createEntry(
        diaryID: "diary-1",
        entryID: "entry-new",
        params: ThingsDiaryEntryParams(
            content: "A new private note",
            bookmarked: true
        )
    )

    #expect(entry.id == "entry-new")
    #expect(entry.content == "A new private note")
    #expect(entry.bookmarked)
    #expect(!entry.archived)
    #expect(transport.lastPutRequest?.url.path == "/api/v1/diaries/diary-1/entries/entry-new")
    #expect(transport.lastPutRequest?.headers["X-Signature"] != nil)
}

@Test("updateEntry preserves the ID and advances the version")
func updatesPlaintextEntry() async throws {
    let transport = PutPlaintextEntryTransport()
    let client = try await entryClient(transport: transport)
    let created = try await client.createEntry(
        diaryID: "diary-1",
        entryID: "entry-new",
        params: ThingsDiaryEntryParams(content: "Before")
    )

    let updated = try await client.updateEntry(
        created,
        params: ThingsDiaryEntryParams(content: "After", archived: true)
    )

    #expect(updated.id == created.id)
    #expect(updated.content == "After")
    #expect(updated.archived)
    #expect(updated.version > created.version)
}

private func entryClient(transport: any ThingsDiaryTransport) async throws -> ThingsDiaryClient {
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

private struct PlaintextEntryTransport: ThingsDiaryTransport {
    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/register":
            return ThingsDiaryHTTPResponse(
                statusCode: 201,
                body: Data(#"{"token":"session-token"}"#.utf8)
            )
        case "/api/v1/diaries/diary-1/keys":
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"keys":[{"id":"key-1","value":"3m8eR+Bkn6YcCbN9wDbVozumBXNjAqCXsV3ll3tfVSaBmi3jDnG2ifEOQZvP6vUQq85YjitnUhfdJDeNmNHhfEE2SC+U54VAVQ2UxtxU5BI=","status":"active"}]}"#.utf8)
            )
        case "/api/v1/diaries/diary-1/entries":
            let token = URLComponents(
                url: request.url,
                resolvingAgainstBaseURL: false
            )?.queryItems?.first(where: { $0.name == "next_page_token" })?.value
            if token == "next-token" {
                return ThingsDiaryHTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"entries":[{"id":"entry-2","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","topic_id":"topic-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CQkJCQkJCQkJCQkJ","encrypted_key_data":"L42MnLb4yWmoasMw7uKr19y4a/s85v/IZ6ZOrt18CXIfzZb+PqQdc6McOLlvo/9n"},"details":{"nonce":"CgoKCgoKCgoKCgoK","data":"KsK3kxoTjtOvjP1vEAhfIyEDccBkzcR+mtesSiyQPoZK+Fhui733ACOXbu580IJGLahNW0V/aHz2GQe2SvlsHst2yDr9SH5Lk3s6JEIbyHBxWnViEHR5XdCP/5mQKVmQ7DfpF+gCR8SaAVpBiCyuNA9I"}}],"next_page_token":null}"#.utf8)
                )
            }
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"entries":[{"id":"entry-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","topic_id":"topic-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CQkJCQkJCQkJCQkJ","encrypted_key_data":"L42MnLb4yWmoasMw7uKr19y4a/s85v/IZ6ZOrt18CXIfzZb+PqQdc6McOLlvo/9n"},"details":{"nonce":"CgoKCgoKCgoKCgoK","data":"KsK3kxoTjtOvjP1vEAhfIyEDccBkzcR+mtesSiyQPoZK+Fhui733ACOXbu580IJGLahNW0V/aHz2GQe2SvlsHst2yDr9SH5Lk3s6JEIbyHBxWnViEHR5XdCP/5mQKVmQ7DfpF+gCR8SaAVpBiCyuNA9I"}}],"next_page_token":"next-token"}"#.utf8)
            )
        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }
}

private final class PutPlaintextEntryTransport: ThingsDiaryTransport, @unchecked Sendable {
    private(set) var lastPutRequest: ThingsDiaryHTTPRequest?

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/register":
            return ThingsDiaryHTTPResponse(
                statusCode: 201,
                body: Data(#"{"token":"session-token"}"#.utf8)
            )
        case "/api/v1/diaries/diary-1/keys":
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"keys":[{"id":"key-1","value":"3m8eR+Bkn6YcCbN9wDbVozumBXNjAqCXsV3ll3tfVSaBmi3jDnG2ifEOQZvP6vUQq85YjitnUhfdJDeNmNHhfEE2SC+U54VAVQ2UxtxU5BI=","status":"active"}]}"#.utf8)
            )
        case "/api/v1/diaries/diary-1/entries/entry-new":
            lastPutRequest = request
            var entry = try #require(
                JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            )
            entry["id"] = "entry-new"
            entry["diary_id"] = "diary-1"
            entry["created_at"] = "2026-10-14T00:00:00Z"
            entry["updated_at"] = "2026-10-14T00:01:40Z"
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: try JSONSerialization.data(withJSONObject: ["entry": entry])
            )
        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }
}
