import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("topics expose plaintext, paginate, encrypt writes, and preserve lifecycle options")
func topicsUsePlaintextContract() async throws {
    let transport = try TopicTemplateTransport()
    let client = try await topicTemplateClient(transport)

    let topics = try await client.allTopics(diaryID: "diary-1")
    #expect(topics.map(\.id) == ["topic-1", "topic-2"])
    #expect(topics[0].title == "Private topic")
    #expect(topics[0].description == "Decrypted description")
    #expect(topics[0].color == "#336699")
    #expect(topics[0].entryPreviewable)
    #expect(topics[1].description.isEmpty)

    let created = try await client.createTopic(
        diaryID: "diary-1",
        topicID: "topic-new",
        params: ThingsDiaryTopicParams(
            title: "New topic",
            description: "Created in Swift",
            color: "#123456",
            entryPreviewable: false,
            defaultTemplateID: "template-1"
        )
    )
    #expect(created.id == "topic-new")
    #expect(created.title == "New topic")
    #expect(!created.entryPreviewable)
    #expect(created.defaultTemplateID == "template-1")
    let createRequest = try #require(transport.lastRequest(method: "PUT"))
    try await expectValidSignature(createRequest, client: client)
    let createBody = try #require(JSONSerialization.jsonObject(with: createRequest.body) as? [String: Any])
    #expect(createBody["details"] != nil)
    #expect(createBody["encryption"] != nil)
    #expect(createBody["title"] == nil)

    let updated = try await client.updateTopic(
        created,
        params: ThingsDiaryTopicParams(
            title: "Renamed topic",
            description: "Updated in Swift",
            color: "#654321"
        )
    )
    #expect(updated.title == "Renamed topic")
    #expect(updated.version > created.version)

    try await client.deleteTopic(
        diaryID: "diary-1",
        topicID: "topic-1",
        deleteEntries: true,
        soft: false
    )
    let deleteQuery = URLComponents(
        url: try #require(transport.requests.last?.url),
        resolvingAgainstBaseURL: false
    )?.queryItems
    #expect(deleteQuery?.first(where: { $0.name == "delete_entries" })?.value == "true")
    #expect(deleteQuery?.first(where: { $0.name == "soft" })?.value == "false")
    #expect(try await client.restoreTopic(diaryID: "diary-1", topicID: "topic-1").title == "Private topic")
}

@Test("templates expose plaintext, paginate, encrypt writes, and restore")
func templatesUsePlaintextContract() async throws {
    let transport = try TopicTemplateTransport()
    let client = try await topicTemplateClient(transport)

    let templates = try await client.allTemplates(diaryID: "diary-1")
    #expect(templates.map(\.id) == ["template-1", "template-2"])
    #expect(templates[0].content == "# Private template")

    let created = try await client.createTemplate(
        diaryID: "diary-1",
        templateID: "template-new",
        params: ThingsDiaryTemplateParams(content: "# Created in Swift")
    )
    #expect(created.id == "template-new")
    #expect(created.content == "# Created in Swift")
    let createRequest = try #require(transport.lastRequest(method: "PUT"))
    try await expectValidSignature(createRequest, client: client)
    let createBody = try #require(JSONSerialization.jsonObject(with: createRequest.body) as? [String: Any])
    #expect(createBody["details"] != nil)
    #expect(createBody["encryption"] != nil)
    #expect(createBody["content"] == nil)

    let updated = try await client.updateTemplate(
        created,
        params: ThingsDiaryTemplateParams(content: "# Updated in Swift")
    )
    #expect(updated.content == "# Updated in Swift")
    #expect(updated.version > created.version)

    try await client.deleteTemplate(diaryID: "diary-1", templateID: "template-1", soft: false)
    let deleteQuery = URLComponents(
        url: try #require(transport.requests.last?.url),
        resolvingAgainstBaseURL: false
    )?.queryItems
    #expect(deleteQuery?.first(where: { $0.name == "soft" })?.value == "false")
    #expect(try await client.restoreTemplate(diaryID: "diary-1", templateID: "template-1").content == "# Private template")
}

private func topicTemplateClient(_ transport: TopicTemplateTransport) async throws -> ThingsDiaryClient {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: transport
    )
    _ = try await client.register(
        login: "person@example.test",
        password: "secret",
        secretKey: TopicTemplateTransport.secretKey,
        kdfSalt: TopicTemplateTransport.salt
    )
    return client
}

private func expectValidSignature(
    _ request: ThingsDiaryHTTPRequest,
    client: ThingsDiaryClient
) async throws {
    let signatureHeader = try #require(request.headers["X-Signature"])
    let signature = try #require(Data(base64Encoded: signatureHeader))
    let authentication = try #require(await client.authentication)
    #expect(try ThingsDiaryCrypto.verify(
        signature,
        for: request.body,
        publicKey: authentication.credentials.signingPublicKey
    ))
}

private final class TopicTemplateTransport: ThingsDiaryTransport, @unchecked Sendable {
    static let secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    static let salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"

    private(set) var requests: [ThingsDiaryHTTPRequest] = []
    private let sealedDiaryKey: String
    private let topicFixtures: [[String: Any]]
    private let templateFixtures: [[String: Any]]

    init() throws {
        let diaryKey = Data(repeating: 7, count: 32)
        let credentials = try ThingsDiaryCrypto.deriveCredentials(
            secretKey: Self.secretKey,
            salt: Self.salt
        )
        sealedDiaryKey = try ThingsDiaryCrypto.seal(
            diaryKey,
            recipientPublicKey: credentials.encryptionPublicKey
        ).base64EncodedString()
        topicFixtures = try [
            Self.topicFixture(id: "topic-1", diaryKey: diaryKey),
            Self.topicFixture(id: "topic-2", diaryKey: diaryKey),
        ]
        templateFixtures = try [
            Self.templateFixture(id: "template-1", diaryKey: diaryKey),
            Self.templateFixture(id: "template-2", diaryKey: diaryKey),
        ]
    }

    func lastRequest(method: String) -> ThingsDiaryHTTPRequest? {
        requests.last(where: { $0.method == method })
    }

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        requests.append(request)
        switch request.url.path {
        case "/api/v1/auth/register":
            return response(201, ["token": "session-token"])
        case "/api/v1/diaries/diary-1/keys":
            return response(200, [
                "keys": [["id": "key-1", "value": sealedDiaryKey, "status": "active"]]
            ])
        case "/api/v1/diaries/diary-1/topics":
            let secondPage = pageToken(request) == "topic-next"
            return response(200, [
                "topics": [topicFixtures[secondPage ? 1 : 0]],
                "next_page_token": secondPage ? NSNull() : "topic-next",
            ])
        case let path where path.hasPrefix("/api/v1/diaries/diary-1/topics/"):
            return try topicResponse(request)
        case "/api/v1/diaries/diary-1/templates":
            let secondPage = pageToken(request) == "template-next"
            return response(200, [
                "templates": [templateFixtures[secondPage ? 1 : 0]],
                "next_page_token": secondPage ? NSNull() : "template-next",
            ])
        case let path where path.hasPrefix("/api/v1/diaries/diary-1/templates/"):
            return try templateResponse(request)
        default:
            Issue.record("Unexpected request: \(request.method) \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }

    private func topicResponse(_ request: ThingsDiaryHTTPRequest) throws -> ThingsDiaryHTTPResponse {
        if request.method == "DELETE" {
            return ThingsDiaryHTTPResponse(statusCode: 204, body: Data())
        }
        if request.method == "PUT" {
            return response(200, ["topic": try entityResponseBody(request, kind: "topic")])
        }
        return response(200, ["topic": topicFixtures[0]])
    }

    private func templateResponse(_ request: ThingsDiaryHTTPRequest) throws -> ThingsDiaryHTTPResponse {
        if request.method == "DELETE" {
            return ThingsDiaryHTTPResponse(statusCode: 204, body: Data())
        }
        if request.method == "PUT" {
            return response(200, ["template": try entityResponseBody(request, kind: "template")])
        }
        return response(200, ["template": templateFixtures[0]])
    }

    private func entityResponseBody(
        _ request: ThingsDiaryHTTPRequest,
        kind: String
    ) throws -> [String: Any] {
        var body = try #require(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        body["id"] = request.url.lastPathComponent
        body["diary_id"] = "diary-1"
        body["created_at"] = "2026-10-14T00:00:00Z"
        body["updated_at"] = "2026-10-14T00:01:40Z"
        if kind == "topic", body["default_template_id"] == nil {
            body["default_template_id"] = NSNull()
        }
        return body
    }

    private func pageToken(_ request: ThingsDiaryHTTPRequest) -> String? {
        URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "next_page_token" })?
            .value
    }

    private func response(_ status: Int, _ object: Any) -> ThingsDiaryHTTPResponse {
        ThingsDiaryHTTPResponse(
            statusCode: status,
            body: try! JSONSerialization.data(withJSONObject: object)
        )
    }

    private static func topicFixture(id: String, diaryKey: Data) throws -> [String: Any] {
        var details: [String: Any] = [
            "title": "Private topic",
            "color": "#336699",
            "entry_previewable": true,
        ]
        if id == "topic-1" {
            details["description"] = "Decrypted description"
        }
        return try fixture(
            id: id,
            diaryKey: diaryKey,
            details: details,
            extra: ["default_template_id": "template-1"]
        )
    }

    private static func templateFixture(id: String, diaryKey: Data) throws -> [String: Any] {
        try fixture(
            id: id,
            diaryKey: diaryKey,
            details: ["content": "# Private template"],
            extra: [:]
        )
    }

    private static func fixture(
        id: String,
        diaryKey: Data,
        details: [String: Any],
        extra: [String: Any]
    ) throws -> [String: Any] {
        let entityKey = Data(repeating: 9, count: 32)
        let encryptedKey = try ThingsDiaryCrypto.encrypt(
            entityKey,
            key: diaryKey,
            nonce: Data(repeating: 10, count: 12)
        )
        let encryptedDetails = try ThingsDiaryCrypto.encrypt(
            JSONSerialization.data(withJSONObject: details),
            key: entityKey,
            nonce: Data(repeating: 11, count: 12)
        )
        var result: [String: Any] = [
            "id": id,
            "diary_id": "diary-1",
            "version": 1_791_970_000_000 as UInt64,
            "created_at": "2026-10-14T00:00:00Z",
            "updated_at": "2026-10-14T00:01:40Z",
            "encryption": [
                "diary_key_id": "key-1",
                "encrypted_key_nonce": encryptedKey.nonce.base64EncodedString(),
                "encrypted_key_data": encryptedKey.ciphertext.base64EncodedString(),
            ],
            "details": [
                "nonce": encryptedDetails.nonce.base64EncodedString(),
                "data": encryptedDetails.ciphertext.base64EncodedString(),
            ],
        ]
        result.merge(extra) { _, new in new }
        return result
    }
}
