import Foundation
import Testing
@testable import ThingsDiaryClient

@Test("getDiaryKeys requests the diary keys with bearer authentication")
func getDiaryKeysRequestsAuthenticatedKeys() async throws {
    let transport = DiaryAPITestTransport()
    let client = try await diaryAPIClient(transport: transport)
    let credentials = try #require(await client.authentication?.credentials)
    let diaryKey = Data(repeating: 7, count: 32)
    let sealedKey = try ThingsDiaryCrypto.seal(diaryKey, recipientPublicKey: credentials.encryptionPublicKey)
    transport.response = Data(#"{"keys":[{"id":"key-1","value":"\#(sealedKey.base64EncodedString())","status":"active"}]}"#.utf8)

    let keys = try await client.getDiaryKeys(diaryID: "diary-1")

    #expect(keys == [ThingsDiaryEncryptionKey(id: "key-1", value: diaryKey, status: .active)])
    #expect(transport.lastRequest?.url.path == "/api/v1/diaries/diary-1/keys")
    #expect(transport.lastRequest?.headers["Authorization"] == "Bearer session-token")
}

@Test("createDiary sends encrypted details and a verifiable signed envelope")
func createDiarySendsEncryptedSignedEnvelope() async throws {
    let transport = DiaryMutationTransport()
    let client = try await diaryAPIClient(transport: transport)
    let auth = try #require(await client.authentication)
    let title = "A private title"
    let description = "Only the client can read this"

    do {
        _ = try await client.createDiary(title: title, description: description)
        Issue.record("Expected the fixture transport's HTTP error")
    } catch let error as ThingsDiaryClientError {
        #expect(error == .httpStatus(422, body: Data("fixture response".utf8)))
    }

    let request = try #require(transport.lastRequest)
    #expect(request.url.path == "/api/v1/diaries")
    #expect(request.method == "POST")
    #expect(request.headers["Authorization"] == "Bearer session-token")
    #expect(request.headers["Content-Type"] == "application/json")
    let signature = try requiredBase64(request.headers["X-Signature"])
    #expect(try ThingsDiaryCrypto.verify(signature, for: request.body, publicKey: auth.credentials.signingPublicKey))

    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    let sealedDiaryKey = try requiredBase64(body["encrypted_diary_key"] as? String)
    let diaryKey = try ThingsDiaryCrypto.openSealedBox(
        sealedDiaryKey,
        recipientPrivateKey: auth.credentials.encryptionPrivateKey,
        recipientPublicKey: auth.credentials.encryptionPublicKey
    )
    let encryption = try #require(body["encryption"] as? [String: String])
    let entityKey = try ThingsDiaryCrypto.decrypt(
        try requiredBase64(encryption["encrypted_key_data"]),
        key: diaryKey,
        nonce: try requiredBase64(encryption["encrypted_key_nonce"])
    )
    let details = try #require(body["details"] as? [String: String])
    let plaintext = try ThingsDiaryCrypto.decrypt(
        try requiredBase64(details["data"]),
        key: entityKey,
        nonce: try requiredBase64(details["nonce"])
    )
    let decodedDetails = try #require(JSONSerialization.jsonObject(with: plaintext) as? [String: String])
    #expect(decodedDetails == ["title": title, "description": description])
}

@Test("Diary decryption accepts the statusless key returned by createDiary")
func decryptsCreateDiaryResponseWithStatuslessKey() async throws {
    let client = try await diaryAPIClient(transport: DiaryMutationTransport())
    let credentials = try #require(await client.authentication?.credentials)
    let diaryKey = Data(repeating: 0x21, count: 32)
    let entityKey = Data(repeating: 0x32, count: 32)
    let encryptedDetails = try ThingsDiaryCrypto.encrypt(
        Data(#"{"title":"Live title","description":"Live description"}"#.utf8),
        key: entityKey
    )
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: diaryKey)
    let sealedDiaryKey = try ThingsDiaryCrypto.seal(
        diaryKey,
        recipientPublicKey: credentials.encryptionPublicKey
    )
    let date = Date(timeIntervalSince1970: 1_791_970_000)
    let wireDiary = WireDiary(
        id: "diary-1",
        version: 1_791_970_000_000,
        createdAt: date,
        updatedAt: date,
        encryptionKeys: [
            WireEncryptionKey(value: sealedDiaryKey.base64EncodedString(), status: ""),
        ],
        encryption: WireDiaryEncryption(
            encryptedKeyNonce: encryptedEntityKey.nonce.base64EncodedString(),
            encryptedKeyData: encryptedEntityKey.ciphertext.base64EncodedString()
        ),
        details: WireEncryptedData(
            nonce: encryptedDetails.nonce.base64EncodedString(),
            data: encryptedDetails.ciphertext.base64EncodedString()
        )
    )

    let diary = try await client.decrypt(wireDiary, credentials: credentials)

    #expect(diary.title == "Live title")
    #expect(diary.description == "Live description")
}

@Test("putDiary sends encrypted details, signature, and the explicit version")
func putDiarySendsSignedEnvelopeAndVersion() async throws {
    let transport = DiaryMutationTransport()
    let client = try await diaryAPIClient(transport: transport)
    let auth = try #require(await client.authentication)
    let activeDiaryKey = Data(repeating: 0x31, count: 32)
    transport.keysBody = Data(#"{"keys":[{"id":"active-key","value":"\#(try ThingsDiaryCrypto.seal(activeDiaryKey, recipientPublicKey: auth.credentials.encryptionPublicKey).base64EncodedString())","status":"active"}]}"#.utf8)
    transport.mutationStatusCode = 409

    do {
        _ = try await client.putDiary(
            id: "diary-1",
            params: ThingsDiaryPutParams(title: "Changed title", description: "Changed description", version: 27)
        )
        Issue.record("Expected the fixture transport's HTTP error")
    } catch let error as ThingsDiaryClientError {
        #expect(error == .httpStatus(409, body: Data("fixture response".utf8)))
    }

    let request = try #require(transport.lastMutationRequest)
    #expect(request.url.path == "/api/v1/diaries/diary-1")
    #expect(request.method == "PUT")
    #expect(request.headers["Authorization"] == "Bearer session-token")
    let signature = try requiredBase64(request.headers["X-Signature"])
    #expect(try ThingsDiaryCrypto.verify(signature, for: request.body, publicKey: auth.credentials.signingPublicKey))
    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    #expect(body["version"] as? Int == 27)
    let encryption = try #require(body["encryption"] as? [String: String])
    #expect(encryption["diary_key_id"] == "active-key")
    let entityKey = try ThingsDiaryCrypto.decrypt(
        try requiredBase64(encryption["encrypted_key_data"]),
        key: activeDiaryKey,
        nonce: try requiredBase64(encryption["encrypted_key_nonce"])
    )
    let details = try #require(body["details"] as? [String: String])
    let plaintext = try ThingsDiaryCrypto.decrypt(
        try requiredBase64(details["data"]),
        key: entityKey,
        nonce: try requiredBase64(details["nonce"])
    )
    let decodedDetails = try #require(JSONSerialization.jsonObject(with: plaintext) as? [String: String])
    #expect(decodedDetails == ["title": "Changed title", "description": "Changed description"])
}

@Test("updateDiary advances the version and sends the edited plaintext details")
func updateDiaryAdvancesVersionAndSendsEditedDetails() async throws {
    let transport = DiaryMutationTransport()
    let client = try await diaryAPIClient(transport: transport)
    let auth = try #require(await client.authentication)
    let activeDiaryKey = Data(repeating: 0x42, count: 32)
    transport.keysBody = Data(#"{"keys":[{"id":"active-key","value":"\#(try ThingsDiaryCrypto.seal(activeDiaryKey, recipientPublicKey: auth.credentials.encryptionPublicKey).base64EncodedString())","status":"active"}]}"#.utf8)
    transport.mutationStatusCode = 409
    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Old title",
        description: "Old description",
        createdAt: .distantPast,
        updatedAt: .distantPast,
        version: 4_000_000_000_000
    )

    do {
        _ = try await client.updateDiary(
            diary,
            params: ThingsDiaryDiaryParams(
                title: "Changed title",
                description: "Changed description"
            )
        )
        Issue.record("Expected the fixture transport's HTTP error")
    } catch let error as ThingsDiaryClientError {
        #expect(error == .httpStatus(409, body: Data("fixture response".utf8)))
    }

    let request = try #require(transport.lastMutationRequest)
    #expect(request.url.path == "/api/v1/diaries/diary-1")
    #expect(request.method == "PUT")
    let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    #expect(body["version"] as? Int == 4_000_000_000_001)
    let encryption = try #require(body["encryption"] as? [String: String])
    let entityKey = try ThingsDiaryCrypto.decrypt(
        try requiredBase64(encryption["encrypted_key_data"]),
        key: activeDiaryKey,
        nonce: try requiredBase64(encryption["encrypted_key_nonce"])
    )
    let details = try #require(body["details"] as? [String: String])
    let plaintext = try ThingsDiaryCrypto.decrypt(
        try requiredBase64(details["data"]),
        key: entityKey,
        nonce: try requiredBase64(details["nonce"])
    )
    let decodedDetails = try #require(JSONSerialization.jsonObject(with: plaintext) as? [String: String])
    #expect(decodedDetails == ["title": "Changed title", "description": "Changed description"])
}

@Test("deleteDiary sends DELETE to the diary path with bearer authentication")
func deleteDiarySendsAuthenticatedDelete() async throws {
    let transport = DiaryMutationTransport()
    transport.mutationStatusCode = 204
    let client = try await diaryAPIClient(transport: transport)

    try await client.deleteDiary(id: "diary-1")

    let request = try #require(transport.lastMutationRequest)
    #expect(request.url.path == "/api/v1/diaries/diary-1")
    #expect(request.method == "DELETE")
    #expect(request.headers["Authorization"] == "Bearer session-token")
    #expect(request.body.isEmpty)
}

@Test("getDiaryChanges sends filters and decodes the change page")
func getDiaryChangesRequestsAndDecodesPage() async throws {
    let transport = DiaryMutationTransport()
    transport.changesBody = Data(#"{"changes":[{"id":"change-1","created_at":"2026-10-14T10:15:30Z","operation":"soft_deleted","entity_type":"entry","entity_id":"entry-9"}],"next_page_token":"next+/="}"#.utf8)
    let client = try await diaryAPIClient(transport: transport)
    let since = ISO8601DateFormatter().date(from: "2026-10-14T10:00:00Z")!

    let page = try await client.getDiaryChanges(
        diaryID: "diary-1",
        since: since,
        limit: 25,
        nextPageToken: "cursor+/="
    )

    let request = try #require(transport.lastRequest)
    #expect(request.url.path == "/api/v1/diaries/diary-1/changes")
    #expect(request.method == "GET")
    #expect(request.headers["Authorization"] == "Bearer session-token")
    let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.first(where: { $0.name == "since" })?.value == "2026-10-14T10:00:00.000Z")
    #expect(query?.first(where: { $0.name == "limit" })?.value == "25")
    #expect(query?.first(where: { $0.name == "next_page_token" })?.value == "cursor+/=")
    #expect(page.changes == [ThingsDiaryChange(
        id: "change-1",
        createdAt: ISO8601DateFormatter().date(from: "2026-10-14T10:15:30Z")!,
        operation: .softDeleted,
        entityType: .entry,
        entityID: "entry-9"
    )])
    #expect(page.nextPageToken == "next+/=")
}

private func diaryAPIClient(transport: any ThingsDiaryTransport) async throws -> ThingsDiaryClient {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: transport
    )
    _ = try await client.login(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"
    )
    return client
}

private func requiredBase64(_ value: String?) throws -> Data {
    let encoded = try #require(value)
    return try #require(Data(base64Encoded: encoded))
}

private final class DiaryAPITestTransport: ThingsDiaryTransport, @unchecked Sendable {
    var response = Data(#"{"keys":[]}"#.utf8)
    private(set) var lastRequest: ThingsDiaryHTTPRequest?

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        if request.url.path == "/api/v1/auth/login" {
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"challenge_id":"challenge-1","nonce":"dGhpbmdzZGlhcnkgY29tcGF0aWJpbGl0eSB2ZWN0b3IgdjE=","kdf_salt":"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"}"#.utf8)
            )
        }
        if request.url.path == "/api/v1/auth/login/verify" {
            return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"token":"session-token"}"#.utf8))
        }
        lastRequest = request
        return ThingsDiaryHTTPResponse(statusCode: 200, body: response)
    }
}

private final class DiaryMutationTransport: ThingsDiaryTransport, @unchecked Sendable {
    var keysBody = Data(#"{"keys":[]}"#.utf8)
    var changesBody = Data(#"{"changes":[],"next_page_token":null}"#.utf8)
    var mutationStatusCode = 422
    private(set) var lastRequest: ThingsDiaryHTTPRequest?
    private(set) var lastMutationRequest: ThingsDiaryHTTPRequest?

    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        if request.url.path == "/api/v1/auth/login" {
            return ThingsDiaryHTTPResponse(
                statusCode: 200,
                body: Data(#"{"challenge_id":"challenge-1","nonce":"dGhpbmdzZGlhcnkgY29tcGF0aWJpbGl0eSB2ZWN0b3IgdjE=","kdf_salt":"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"}"#.utf8)
            )
        }
        if request.url.path == "/api/v1/auth/login/verify" {
            return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"token":"session-token"}"#.utf8))
        }
        if request.url.path == "/api/v1/diaries/diary-1/keys" {
            lastRequest = request
            return ThingsDiaryHTTPResponse(statusCode: 200, body: keysBody)
        }
        if request.url.path == "/api/v1/diaries/diary-1/changes" {
            lastRequest = request
            return ThingsDiaryHTTPResponse(statusCode: 200, body: changesBody)
        }
        lastRequest = request
        lastMutationRequest = request
        if request.method == "DELETE" {
            return ThingsDiaryHTTPResponse(statusCode: mutationStatusCode, body: Data())
        }
        return ThingsDiaryHTTPResponse(statusCode: mutationStatusCode, body: Data("fixture response".utf8))
    }
}
