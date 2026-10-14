import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("topic endpoints preserve pagination, versioned writes, deletion options, and signatures")
func topicEndpointsUseOpenAPIRequests() async throws {
    let transport = TopicTemplateTransport()
    let client = try await topicTemplateClient(transport)
    let topic = topicFixture()

    let page = try await client.topics(diaryID: "diary-1", nextPageToken: "cursor+/=")
    #expect(page.items == [topic])
    #expect(page.nextPageToken == "topic-next")
    #expect(URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "cursor+/=")

    #expect(try await client.getTopic(diaryID: "diary-1", topicID: "topic-1") == topic)
    #expect(try await client.putTopic(
        diaryID: "diary-1", topicID: "topic-1", version: 1_791_970_000_000,
        defaultTemplateID: "template-1", encryption: topic.encryption, details: topic.details
    ) == topic)
    let put = try #require(transport.requests.last)
    let signatureHeader = try #require(put.headers["X-Signature"])
    let signature = try #require(Data(base64Encoded: signatureHeader))
    let auth = try #require(await client.authentication)
    #expect(try ThingsDiaryCrypto.verify(signature, for: put.body, publicKey: auth.credentials.signingPublicKey))
    let body = try #require(JSONSerialization.jsonObject(with: put.body) as? [String: Any])
    #expect(body["version"] as? Int == 1_791_970_000_000)
    #expect(body["default_template_id"] as? String == "template-1")

    try await client.deleteTopic(diaryID: "diary-1", topicID: "topic-1", deleteEntries: true, soft: false)
    let deleteQuery = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(deleteQuery?.first(where: { $0.name == "delete_entries" })?.value == "true")
    #expect(deleteQuery?.first(where: { $0.name == "soft" })?.value == "false")
    #expect(try await client.restoreTopic(diaryID: "diary-1", topicID: "topic-1") == topic)
}

@Test("template endpoints preserve pagination, versioned writes, deletion options, and signatures")
func templateEndpointsUseOpenAPIRequests() async throws {
    let transport = TopicTemplateTransport()
    let client = try await topicTemplateClient(transport)
    let template = templateFixture()

    let page = try await client.templates(diaryID: "diary-1", nextPageToken: "next+/=")
    #expect(page.items == [template])
    #expect(page.nextPageToken == "template-next")
    #expect(try await client.getTemplate(diaryID: "diary-1", templateID: "template-1") == template)
    #expect(try await client.putTemplate(
        diaryID: "diary-1", templateID: "template-1", version: 1_791_970_000_000,
        encryption: template.encryption, details: template.details
    ) == template)
    let put = try #require(transport.requests.last)
    let signatureHeader = try #require(put.headers["X-Signature"])
    let signature = try #require(Data(base64Encoded: signatureHeader))
    let auth = try #require(await client.authentication)
    #expect(try ThingsDiaryCrypto.verify(signature, for: put.body, publicKey: auth.credentials.signingPublicKey))
    #expect((try #require(JSONSerialization.jsonObject(with: put.body) as? [String: Any]))["version"] as? Int == 1_791_970_000_000)

    try await client.deleteTemplate(diaryID: "diary-1", templateID: "template-1", soft: false)
    #expect(URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "false")
    #expect(try await client.restoreTemplate(diaryID: "diary-1", templateID: "template-1") == template)
}

private func topicTemplateClient(_ transport: TopicTemplateTransport) async throws -> ThingsDiaryClient {
    let client = ThingsDiaryClient(baseURL: URL(string: "https://example.test/api")!, transport: transport)
    _ = try await client.register(login: "person@example.test", password: "secret", secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6", kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
    return client
}

private func topicFixture() -> ThingsDiaryTopic {
    ThingsDiaryTopic(id: "topic-1", diaryID: "diary-1", version: 1_791_970_000_000,
        createdAt: Date(timeIntervalSince1970: 1_791_936_000), updatedAt: Date(timeIntervalSince1970: 1_791_936_100),
        defaultTemplateID: "template-1", encryption: entityEncryption(), details: entityDetails())
}

private func templateFixture() -> ThingsDiaryTemplate {
    ThingsDiaryTemplate(id: "template-1", diaryID: "diary-1", version: 1_791_970_000_000,
        createdAt: Date(timeIntervalSince1970: 1_791_936_000), updatedAt: Date(timeIntervalSince1970: 1_791_936_100),
        encryption: entityEncryption(), details: entityDetails())
}

private func entityEncryption() -> ThingsDiaryEntityEncryption {
    ThingsDiaryEntityEncryption(diaryKeyID: "key-1", encryptedKeyNonce: Data([8]), encryptedKeyData: Data([9]))
}

private func entityDetails() -> ThingsDiaryEncryptedPayload {
    ThingsDiaryEncryptedPayload(nonce: Data([1]), data: Data([1, 2, 3]))
}

private final class TopicTemplateTransport: ThingsDiaryTransport, @unchecked Sendable {
    private(set) var requests: [ThingsDiaryHTTPRequest] = []
    private let topic = #"{"id":"topic-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","default_template_id":"template-1","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CA==","encrypted_key_data":"CQ=="},"details":{"nonce":"AQ==","data":"AQID"}}"#
    private let template = #"{"id":"template-1","diary_id":"diary-1","version":1791970000000,"created_at":"2026-10-14T00:00:00Z","updated_at":"2026-10-14T00:01:40Z","encryption":{"diary_key_id":"key-1","encrypted_key_nonce":"CA==","encrypted_key_data":"CQ=="},"details":{"nonce":"AQ==","data":"AQID"}}"#

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        requests.append(request)
        switch request.url.path {
        case "/api/v1/auth/register": return response(201, #"{"token":"session-token"}"#)
        case "/api/v1/diaries/diary-1/topics": return response(200, #"{"topics":["# + topic + #"],"next_page_token":"topic-next"}"#)
        case "/api/v1/diaries/diary-1/topics/topic-1":
            return request.method == "DELETE" ? ThingsDiaryHTTPResponse(statusCode: 204, body: Data()) : response(200, #"{"topic":"# + topic + #"}"#)
        case "/api/v1/diaries/diary-1/topics/topic-1/restore": return response(200, #"{"topic":"# + topic + #"}"#)
        case "/api/v1/diaries/diary-1/templates": return response(200, #"{"templates":["# + template + #"],"next_page_token":"template-next"}"#)
        case "/api/v1/diaries/diary-1/templates/template-1":
            return request.method == "DELETE" ? ThingsDiaryHTTPResponse(statusCode: 204, body: Data()) : response(200, #"{"template":"# + template + #"}"#)
        case "/api/v1/diaries/diary-1/templates/template-1/restore": return response(200, #"{"template":"# + template + #"}"#)
        default: Issue.record("Unexpected request: \(request.url)"); return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }

    private func response(_ status: Int, _ body: String) -> ThingsDiaryHTTPResponse {
        ThingsDiaryHTTPResponse(statusCode: status, body: Data(body.utf8))
    }
}
