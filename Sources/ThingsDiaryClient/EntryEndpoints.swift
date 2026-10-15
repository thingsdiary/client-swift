import CryptoKit
import Foundation

extension ThingsDiaryClient {
    public func entries(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<ThingsDiaryEntry> {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let page = try await encryptedEntries(
            diaryID: diaryID,
            nextPageToken: nextPageToken
        )
        return ThingsDiaryPage(
            items: try page.items.map { try decrypt($0, diaryKeys: diaryKeys) },
            nextPageToken: page.nextPageToken
        )
    }

    public func allEntries(diaryID: String) async throws -> [ThingsDiaryEntry] {
        var result: [ThingsDiaryEntry] = []
        var nextPageToken: String?

        repeat {
            let page = try await entries(
                diaryID: diaryID,
                nextPageToken: nextPageToken
            )
            result.append(contentsOf: page.items)
            nextPageToken = page.nextPageToken
        } while nextPageToken != nil

        return result
    }

    public func createEntry(
        diaryID: String,
        entryID: String = UUID().uuidString.lowercased(),
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let version = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try await putPlaintextEntry(
            diaryID: diaryID,
            entryID: entryID,
            version: version,
            params: params,
            diaryKeys: diaryKeys
        )
    }

    public func updateEntry(
        _ entry: ThingsDiaryEntry,
        params: ThingsDiaryEntryParams
    ) async throws -> ThingsDiaryEntry {
        let diaryKeys = try await getDiaryKeys(diaryID: entry.diaryID)
        let currentVersion = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try await putPlaintextEntry(
            diaryID: entry.diaryID,
            entryID: entry.id,
            version: max(currentVersion, entry.version + 1),
            params: params,
            diaryKeys: diaryKeys
        )
    }

    func encryptedEntries(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<WireEntry> {
        var query: [URLQueryItem] = []
        if let nextPageToken {
            query.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
        }
        let response: EntriesResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "entries"],
            method: "GET",
            query: query
        )
        return ThingsDiaryPage(items: response.entries, nextPageToken: response.nextPageToken)
    }

    public func getEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        return try decrypt(
            try await encryptedEntry(diaryID: diaryID, entryID: entryID),
            diaryKeys: diaryKeys
        )
    }

    func encryptedEntry(diaryID: String, entryID: String) async throws -> WireEntry {
        let response: EntryResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "entries", entryID],
            method: "GET"
        )
        return response.entry
    }

    func putEncryptedEntry(
        diaryID: String,
        entryID: String,
        version: UInt64,
        topicID: String? = nil,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload,
        preview: ThingsDiaryEncryptedPayload
    ) async throws -> WireEntry {
        let body = try JSONEncoder().encode(PutEntryBody(
            version: version,
            topicID: topicID,
            encryption: encryption,
            details: details,
            preview: preview
        ))
        let response: EntryResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "entries", entryID],
            method: "PUT",
            body: body,
            signed: true
        )
        return response.entry
    }

    func putPlaintextEntry(
        diaryID: String,
        entryID: String,
        version: UInt64,
        params: ThingsDiaryEntryParams,
        diaryKeys: [ThingsDiaryEncryptionKey]
    ) async throws -> ThingsDiaryEntry {
        guard let activeKey = diaryKeys.first(where: { $0.status == .active }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }
        let entityKey = randomEntryKey()
        let plaintext = try JSONEncoder().encode(EntryDetailsRequest(
            content: params.content,
            archived: params.archived,
            bookmarked: params.bookmarked,
            previewHidden: params.previewHidden
        ))
        let details = try ThingsDiaryCrypto.encrypt(plaintext, key: entityKey)
        let preview = try ThingsDiaryCrypto.encrypt(plaintext, key: entityKey)
        let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(
            entityKey,
            key: activeKey.value
        )
        let wireEntry = try await putEncryptedEntry(
            diaryID: diaryID,
            entryID: entryID,
            version: version,
            topicID: params.topicID,
            encryption: ThingsDiaryEntityEncryption(
                diaryKeyID: activeKey.id,
                encryptedKeyNonce: encryptedEntityKey.nonce,
                encryptedKeyData: encryptedEntityKey.ciphertext
            ),
            details: ThingsDiaryEncryptedPayload(
                nonce: details.nonce,
                data: details.ciphertext
            ),
            preview: ThingsDiaryEncryptedPayload(
                nonce: preview.nonce,
                data: preview.ciphertext
            )
        )
        return try decrypt(wireEntry, diaryKeys: diaryKeys)
    }

    public func deleteEntry(
        diaryID: String,
        entryID: String,
        soft: Bool? = nil
    ) async throws {
        var query: [URLQueryItem] = []
        if let soft {
            query.append(URLQueryItem(name: "soft", value: soft ? "true" : "false"))
        }
        try await sendEntityNoContent(
            path: ["v1", "diaries", diaryID, "entries", entryID],
            method: "DELETE",
            query: query
        )
    }

    public func restoreEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let response: EntryResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "entries", entryID, "restore"],
            method: "POST"
        )
        return try decrypt(response.entry, diaryKeys: diaryKeys)
    }

    func decrypt(
        _ entry: WireEntry,
        diaryKeys: [ThingsDiaryEncryptionKey]
    ) throws -> ThingsDiaryEntry {
        guard let diaryKey = diaryKeys.first(where: {
            $0.id == entry.encryption.diaryKeyID
        }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }
        let entityKey = try ThingsDiaryCrypto.decrypt(
            entry.encryption.encryptedKeyData,
            key: diaryKey.value,
            nonce: entry.encryption.encryptedKeyNonce
        )
        let detailsData = try ThingsDiaryCrypto.decrypt(
            entry.details.data,
            key: entityKey,
            nonce: entry.details.nonce
        )
        let details = try JSONDecoder().decode(EntryDetails.self, from: detailsData)
        return ThingsDiaryEntry(
            id: entry.id,
            diaryID: entry.diaryID,
            content: details.content,
            topicID: entry.topicID,
            archived: details.archived,
            bookmarked: details.bookmarked,
            previewHidden: details.previewHidden,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            version: entry.version
        )
    }

    func sendEntityRequest<Response: Decodable>(
        path: [String],
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        signed: Bool = false
    ) async throws -> Response {
        guard let authentication else {
            throw ThingsDiaryClientError.notAuthenticated
        }
        var requestURL = url(path)
        if !query.isEmpty {
            requestURL.append(queryItems: query)
        }
        var headers = ["Authorization": "Bearer \(authentication.token)"]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        if signed, let body {
            headers["X-Signature"] = try ThingsDiaryCrypto.sign(
                body,
                privateKey: authentication.credentials.signingPrivateKey
            ).base64EncodedString()
        }
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: requestURL,
            method: method,
            headers: headers,
            body: body ?? Data()
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
        let decoder = JSONDecoder.thingsDiary()
        return try decoder.decode(Response.self, from: response.body)
    }

    func sendEntityNoContent(
        path: [String],
        method: String,
        query: [URLQueryItem] = []
    ) async throws {
        guard let authentication else {
            throw ThingsDiaryClientError.notAuthenticated
        }
        var requestURL = url(path)
        if !query.isEmpty {
            requestURL.append(queryItems: query)
        }
        let response = try await transport.send(ThingsDiaryHTTPRequest(
            url: requestURL,
            method: method,
            headers: ["Authorization": "Bearer \(authentication.token)"]
        ))
        guard response.statusCode == 204 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
    }
}

private struct PutEntryBody: Encodable {
    let version: UInt64
    let topicID: String?
    let encryption: ThingsDiaryEntityEncryption
    let details: ThingsDiaryEncryptedPayload
    let preview: ThingsDiaryEncryptedPayload

    enum CodingKeys: String, CodingKey {
        case version, encryption, details, preview
        case topicID = "topic_id"
    }
}

private struct EntryResponse: Decodable {
    let entry: WireEntry
}

private struct EntriesResponse: Decodable {
    let entries: [WireEntry]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case nextPageToken = "next_page_token"
    }
}

private struct EntryDetails: Decodable {
    let content: String
    let archived: Bool
    let bookmarked: Bool
    let previewHidden: Bool

    enum CodingKeys: String, CodingKey {
        case content, archived, bookmarked
        case previewHidden = "preview_hidden"
    }
}

private struct EntryDetailsRequest: Encodable {
    let content: String
    let archived: Bool
    let bookmarked: Bool
    let previewHidden: Bool

    enum CodingKeys: String, CodingKey {
        case content, archived, bookmarked
        case previewHidden = "preview_hidden"
    }
}

private func randomEntryKey() -> Data {
    let key = SymmetricKey(size: .bits256)
    return key.withUnsafeBytes { Data($0) }
}
