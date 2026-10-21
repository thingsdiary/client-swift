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
        var request = Io_Thingsdiary_V1_ListEntriesRequest()
        request.diaryID = diaryID
        request.page.pageToken = nextPageToken ?? ""
        let response = try await rpc(
            "io.thingsdiary.v1.entry.list",
            request: request,
            response: Io_Thingsdiary_V1_ListEntriesResponse.self
        )
        return ThingsDiaryPage(
            items: response.entries.map(\.wire),
            nextPageToken: response.page.nextPageToken.nilIfEmpty
        )
    }

    public func getEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        return try decrypt(
            try await encryptedEntry(diaryID: diaryID, entryID: entryID),
            diaryKeys: diaryKeys
        )
    }

    func encryptedEntry(diaryID: String, entryID: String) async throws -> WireEntry {
        var request = Io_Thingsdiary_V1_GetEntryRequest()
        request.diaryID = diaryID
        request.entryID = entryID
        let response = try await rpc(
            "io.thingsdiary.v1.entry.get",
            request: request,
            response: Io_Thingsdiary_V1_GetEntryResponse.self
        )
        return response.entry.wire
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
        var request = Io_Thingsdiary_V1_PutEntryRequest()
        request.diaryID = diaryID
        request.entryID = entryID
        request.version = version
        if let topicID { request.topicID = topicID }
        request.encryption = Io_Thingsdiary_V1_Encryption(encryption)
        request.details = Io_Thingsdiary_V1_EncryptedData(details)
        request.preview = Io_Thingsdiary_V1_EncryptedData(preview)
        let response = try await rpc(
            "io.thingsdiary.v1.entry.put",
            request: request,
            response: Io_Thingsdiary_V1_PutEntryResponse.self
        )
        return response.entry.wire
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
        var request = Io_Thingsdiary_V1_DeleteEntryRequest()
        request.diaryID = diaryID
        request.entryID = entryID
        if let soft { request.soft = soft }
        _ = try await rpc(
            "io.thingsdiary.v1.entry.delete",
            request: request,
            response: Io_Thingsdiary_V1_DeleteEntryResponse.self
        )
    }

    public func restoreEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        var request = Io_Thingsdiary_V1_RestoreEntryRequest()
        request.diaryID = diaryID
        request.entryID = entryID
        let response = try await rpc(
            "io.thingsdiary.v1.entry.restore",
            request: request,
            response: Io_Thingsdiary_V1_RestoreEntryResponse.self
        )
        return try decrypt(response.entry.wire, diaryKeys: diaryKeys)
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
