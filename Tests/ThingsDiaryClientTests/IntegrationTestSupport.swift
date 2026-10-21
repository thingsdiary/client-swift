import Foundation
import SwiftProtobuf
import Testing
@testable import ThingsDiaryClient

struct IntegrationTestSession {
    let client: ThingsDiaryClient
    let login: String
    let password: String
    let secretKey: String
}

func makeServerTestSession(resource: String) async throws -> IntegrationTestSession {
    let environment = ProcessInfo.processInfo.environment
    let baseURL = try #require(URL(string: environment["BASE_URL"] ?? "http://127.0.0.1:8081/api"))
    let realtimeURL = try #require(
        URL(string: environment["REALTIME_URL"] ?? "ws://127.0.0.1:8000/connection/websocket")
    )
    return try await makeIntegrationTestSession(
        resource: resource,
        baseURL: baseURL,
        realtimeURL: realtimeURL
    )
}

func makeProductionTestSession(resource: String) async throws -> IntegrationTestSession {
    try await makeIntegrationTestSession(
        resource: resource,
        baseURL: ThingsDiaryClient.productionURL,
        realtimeURL: nil
    )
}

private func makeIntegrationTestSession(
    resource: String,
    baseURL: URL,
    realtimeURL: URL?
) async throws -> IntegrationTestSession {
    let identifier = UUID().uuidString.lowercased()
    let login = "integration.swift.\(resource).\(identifier)@thingsdiary.io"
    let password = "Swift integration \(identifier)"
    let secretKey = ThingsDiarySecretKey.generate().rawValue
    let kdfSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let client = ThingsDiaryClient(baseURL: baseURL, realtimeURL: realtimeURL)

    let authentication = try await client.register(
        login: login,
        password: password,
        secretKey: secretKey,
        kdfSalt: kdfSalt
    )
    #expect(!authentication.token.isEmpty)
    try await client.connect()

    return IntegrationTestSession(
        client: client,
        login: login,
        password: password,
        secretKey: secretKey
    )
}

func makeServerTestDiary(
    client: ThingsDiaryClient,
    resource: String
) async throws -> ThingsDiaryDiary {
    try await client.createDiary(
        title: "Swift \(resource) test",
        description: "Diary for the Swift \(resource) integration test"
    )
}

func makeServerTestClient() throws -> ThingsDiaryClient {
    let environment = ProcessInfo.processInfo.environment
    let baseURL = try #require(URL(string: environment["BASE_URL"] ?? "http://127.0.0.1:8081/api"))
    let realtimeURL = try #require(
        URL(string: environment["REALTIME_URL"] ?? "ws://127.0.0.1:8000/connection/websocket")
    )

    return ThingsDiaryClient(baseURL: baseURL, realtimeURL: realtimeURL)
}

func authenticatedMockClient(realtime: MockRealtimeTransport) async throws -> ThingsDiaryClient {
    let client = ThingsDiaryClient(
        baseURL: URL(string: "https://example.test/api")!,
        transport: RealtimeHTTPTransport(),
        realtimeTransport: realtime
    )
    _ = try await client.register(
        login: "person@example.test",
        password: "secret",
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
        kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
    )
    return client
}

func realtimeTestCredentials() throws -> ThingsDiaryCredentials {
    try ThingsDiaryCrypto.deriveCredentials(
        secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
        salt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
    )
}

func listDiariesTestResponse(
    credentials: ThingsDiaryCredentials
) throws -> Io_Thingsdiary_V1_ListDiariesResponse {
    let diaryKey = Data(repeating: 7, count: 32)
    let entityKey = Data(repeating: 9, count: 32)
    let sealedDiaryKey = try ThingsDiaryCrypto.seal(
        diaryKey,
        recipientPublicKey: credentials.encryptionPublicKey
    )
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: diaryKey)
    let encryptedDetails = try ThingsDiaryCrypto.encrypt(
        Data(#"{"title":"Private title","description":"Private description"}"#.utf8),
        key: entityKey
    )

    var key = Io_Thingsdiary_V1_DiaryEncryptionKey()
    key.id = "key-1"
    key.value = sealedDiaryKey
    key.status = .active

    var diary = Io_Thingsdiary_V1_Diary()
    diary.id = "diary-1"
    diary.version = 42
    diary.createdAt.seconds = 1_700_000_000
    diary.updatedAt.seconds = 1_700_000_001
    diary.encryptionKeys = [key]
    diary.encryption.diaryKeyID = "key-1"
    diary.encryption.encryptedKeyNonce = encryptedEntityKey.nonce
    diary.encryption.encryptedKeyData = encryptedEntityKey.ciphertext
    diary.details.nonce = encryptedDetails.nonce
    diary.details.data = encryptedDetails.ciphertext

    var response = Io_Thingsdiary_V1_ListDiariesResponse()
    response.diaries = [diary]
    response.page.nextPageToken = "next"
    return response
}

struct RealtimeHTTPTransport: ThingsDiaryTransport {
    func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
        switch request.url.path {
        case "/api/v1/auth/register":
            return ThingsDiaryHTTPResponse(statusCode: 201, body: Data(#"{"token":"session-token"}"#.utf8))
        case "/api/v1/realtime/token":
            #expect(request.headers["Authorization"] == "Bearer session-token")
            return ThingsDiaryHTTPResponse(statusCode: 200, body: Data(#"{"token":"realtime-token"}"#.utf8))
        default:
            Issue.record("Unexpected request: \(request.url)")
            return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
        }
    }
}

final class MockRealtimeTransport: ThingsDiaryRealtimeTransport, @unchecked Sendable {
    private let broadcaster = RealtimeEventBroadcaster()
    var connectedToken: String?
    var handler: @Sendable (String, Data) throws -> Data = { _, _ in Data() }

    func connect(
        token: String,
        tokenProvider: @escaping @Sendable () async throws -> String
    ) async throws {
        connectedToken = token
    }

    func disconnect() async {}

    func rpc(method: String, data: Data) async throws -> Data {
        let signed = try Io_Thingsdiary_V1_SignedEnvelope(serializedBytes: data)
        let credentials = try realtimeTestCredentials()

        #expect(try ThingsDiaryCrypto.verify(
            signed.signature,
            for: signed.envelope,
            publicKey: credentials.signingPublicKey
        ))

        let envelope = try Io_Thingsdiary_V1_Envelope(serializedBytes: signed.envelope)

        #expect(envelope.version == 1)
        #expect(envelope.method == method)
        #expect(UUID(uuidString: envelope.operationID) != nil)

        return try handler(method, envelope.payload)
    }

    func events() -> AsyncStream<Data> { broadcaster.stream() }
    func publish(_ data: Data) { broadcaster.yield(data) }
}
