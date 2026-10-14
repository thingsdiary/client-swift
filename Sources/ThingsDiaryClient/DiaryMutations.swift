import Foundation
import CryptoKit

extension ThingsDiaryClient {
    public func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
        guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }

        let diaryKey = randomSymmetricKey()
        let entityKey = randomSymmetricKey()
        let details = try encodeDetails(title: params.title, description: params.description)
        let encryptedDetails = try ThingsDiaryCrypto.encrypt(details, key: entityKey)
        let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: diaryKey)
        let sealedDiaryKey = try ThingsDiaryCrypto.seal(
            diaryKey,
            recipientPublicKey: authentication.credentials.encryptionPublicKey
        )
        let body = CreateDiaryWireRequest(
            encryptedDiaryKey: sealedDiaryKey.base64EncodedString(),
            encryption: DiaryEncryptionWireRequest(
                encryptedKeyNonce: encryptedEntityKey.nonce.base64EncodedString(),
                encryptedKeyData: encryptedEntityKey.ciphertext.base64EncodedString()
            ),
            details: WireEncryptedDataRequest(
                nonce: encryptedDetails.nonce.base64EncodedString(),
                data: encryptedDetails.ciphertext.base64EncodedString()
            )
        )
        let encodedBody = try JSONEncoder().encode(body)
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: url(["v1", "diaries"]),
            method: "POST",
            headers: signedHeaders(encodedBody, authentication: authentication),
            body: encodedBody
        ))
        guard response.statusCode == 201 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
        let decoder = JSONDecoder.thingsDiary()
        let diary = try decoder.decode(DiaryMutationResponse.self, from: response.body).diary
        return try decrypt(diary, credentials: authentication.credentials)
    }

    public func createDiary(title: String, description: String) async throws -> ThingsDiaryDiary {
        try await createDiary(ThingsDiaryCreateParams(title: title, description: description))
    }

    public func putDiary(id: String, params: ThingsDiaryPutParams) async throws -> ThingsDiaryDiary {
        guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }
        guard let activeKey = try await getDiaryKeys(diaryID: id).first(where: { $0.status == .active }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }

        let entityKey = randomSymmetricKey()
        let details = try encodeDetails(title: params.title, description: params.description)
        let encryptedDetails = try ThingsDiaryCrypto.encrypt(details, key: entityKey)
        let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: activeKey.value)
        let body = PutDiaryWireRequest(
            details: WireEncryptedDataRequest(
                nonce: encryptedDetails.nonce.base64EncodedString(),
                data: encryptedDetails.ciphertext.base64EncodedString()
            ),
            encryption: PutDiaryEncryptionWireRequest(
                diaryKeyID: activeKey.id,
                encryptedKeyNonce: encryptedEntityKey.nonce.base64EncodedString(),
                encryptedKeyData: encryptedEntityKey.ciphertext.base64EncodedString()
            ),
            version: params.version
        )
        let encodedBody = try JSONEncoder().encode(body)
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: url(["v1", "diaries", id]),
            method: "PUT",
            headers: signedHeaders(encodedBody, authentication: authentication),
            body: encodedBody
        ))
        guard response.statusCode == 200 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
        let decoder = JSONDecoder.thingsDiary()
        let diary = try decoder.decode(DiaryMutationResponse.self, from: response.body).diary
        return try decrypt(diary, credentials: authentication.credentials)
    }

    public func updateDiary(id: String, params: ThingsDiaryPutParams) async throws -> ThingsDiaryDiary {
        try await putDiary(id: id, params: params)
    }

    public func deleteDiary(id: String) async throws {
        guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: url(["v1", "diaries", id]),
            method: "DELETE",
            headers: ["Authorization": "Bearer \(authentication.token)"]
        ))
        guard response.statusCode == 204 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
    }

    public func getDiaryKeys(diaryID: String) async throws -> [ThingsDiaryEncryptionKey] {
        guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: url(["v1", "diaries", diaryID, "keys"]),
            method: "GET",
            headers: ["Authorization": "Bearer \(authentication.token)"]
        ))
        guard response.statusCode == 200 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
        let wireResponse = try JSONDecoder().decode(DiaryKeysResponse.self, from: response.body)
        return try wireResponse.keys.map { key in
            guard let sealedKey = Data(base64Encoded: key.value) else {
                throw ThingsDiaryClientError.invalidBase64
            }
            let openedKey = try ThingsDiaryCrypto.openSealedBox(
                sealedKey,
                recipientPrivateKey: authentication.credentials.encryptionPrivateKey,
                recipientPublicKey: authentication.credentials.encryptionPublicKey
            )
            return ThingsDiaryEncryptionKey(id: key.id, value: openedKey, status: key.status)
        }
    }

    public func getDiaryChanges(
        diaryID: String,
        since: Date? = nil,
        limit: Int? = nil,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryChangesPage {
        guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }
        var requestURL = url(["v1", "diaries", diaryID, "changes"])
        var queryItems: [URLQueryItem] = []
        if let nextPageToken { queryItems.append(URLQueryItem(name: "next_page_token", value: nextPageToken)) }
        if let since {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            queryItems.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
        }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if !queryItems.isEmpty {
            var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            requestURL = components.url!
        }
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: requestURL,
            method: "GET",
            headers: ["Authorization": "Bearer \(authentication.token)"]
        ))
        guard response.statusCode == 200 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
        let decoder = JSONDecoder.thingsDiary()
        let page = try decoder.decode(DiaryChangesResponse.self, from: response.body)
        return ThingsDiaryChangesPage(changes: page.changes, nextPageToken: page.nextPageToken)
    }

    private func encodeDetails(title: String, description: String) throws -> Data {
        try JSONEncoder().encode(DiaryDetailsRequest(title: title, description: description))
    }

    private func signedHeaders(
        _ body: Data,
        authentication: ThingsDiaryAuthState
    ) throws -> [String: String] {
        let signature = try ThingsDiaryCrypto.sign(body, privateKey: authentication.credentials.signingPrivateKey)
        return [
            "Authorization": "Bearer \(authentication.token)",
            "Content-Type": "application/json",
            "X-Signature": signature.base64EncodedString(),
        ]
    }
}

private struct WireEncryptedDataRequest: Encodable {
    let nonce: String
    let data: String
}

private struct DiaryEncryptionWireRequest: Encodable {
    let encryptedKeyNonce: String
    let encryptedKeyData: String

    enum CodingKeys: String, CodingKey {
        case encryptedKeyNonce = "encrypted_key_nonce"
        case encryptedKeyData = "encrypted_key_data"
    }
}

private struct CreateDiaryWireRequest: Encodable {
    let encryptedDiaryKey: String
    let encryption: DiaryEncryptionWireRequest
    let details: WireEncryptedDataRequest

    enum CodingKeys: String, CodingKey {
        case encryptedDiaryKey = "encrypted_diary_key"
        case encryption, details
    }
}

private struct PutDiaryEncryptionWireRequest: Encodable {
    let diaryKeyID: String
    let encryptedKeyNonce: String
    let encryptedKeyData: String

    enum CodingKeys: String, CodingKey {
        case diaryKeyID = "diary_key_id"
        case encryptedKeyNonce = "encrypted_key_nonce"
        case encryptedKeyData = "encrypted_key_data"
    }
}

private struct PutDiaryWireRequest: Encodable {
    let details: WireEncryptedDataRequest
    let encryption: PutDiaryEncryptionWireRequest
    let version: UInt64
}

private struct DiaryDetailsRequest: Encodable {
    let title: String
    let description: String
}

private struct DiaryMutationResponse: Decodable {
    let diary: WireDiary
}

private struct DiaryKeysResponse: Decodable {
    let keys: [DiaryKeyResponse]
}

private struct DiaryKeyResponse: Decodable {
    let id: String
    let value: String
    let status: ThingsDiaryEncryptionKeyStatus
}

private struct DiaryChangesResponse: Decodable {
    let changes: [ThingsDiaryChange]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case changes
        case nextPageToken = "next_page_token"
    }
}

private func randomSymmetricKey() -> Data {
    let key = SymmetricKey(size: .bits256)
    return key.withUnsafeBytes { Data($0) }
}
