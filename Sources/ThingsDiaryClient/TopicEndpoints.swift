import CryptoKit
import Foundation

extension ThingsDiaryClient {
    public func topics(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<ThingsDiaryTopic> {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let page = try await encryptedTopics(
            diaryID: diaryID,
            nextPageToken: nextPageToken
        )
        return ThingsDiaryPage(
            items: try page.items.map { try decrypt($0, diaryKeys: diaryKeys) },
            nextPageToken: page.nextPageToken
        )
    }

    public func allTopics(diaryID: String) async throws -> [ThingsDiaryTopic] {
        var result: [ThingsDiaryTopic] = []
        var nextPageToken: String?

        repeat {
            let page = try await topics(diaryID: diaryID, nextPageToken: nextPageToken)
            result.append(contentsOf: page.items)
            nextPageToken = page.nextPageToken
        } while nextPageToken != nil

        return result
    }

    public func createTopic(
        diaryID: String,
        topicID: String = UUID().uuidString.lowercased(),
        params: ThingsDiaryTopicParams
    ) async throws -> ThingsDiaryTopic {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let version = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try await putPlaintextTopic(
            diaryID: diaryID,
            topicID: topicID,
            version: version,
            params: params,
            diaryKeys: diaryKeys
        )
    }

    public func updateTopic(
        _ topic: ThingsDiaryTopic,
        params: ThingsDiaryTopicParams
    ) async throws -> ThingsDiaryTopic {
        let diaryKeys = try await getDiaryKeys(diaryID: topic.diaryID)
        let currentVersion = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try await putPlaintextTopic(
            diaryID: topic.diaryID,
            topicID: topic.id,
            version: max(currentVersion, topic.version + 1),
            params: params,
            diaryKeys: diaryKeys
        )
    }

    func encryptedTopics(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<WireTopic> {
        var request = Io_Thingsdiary_V1_ListTopicsRequest()
        request.diaryID = diaryID
        request.page.pageToken = nextPageToken ?? ""
        let response = try await rpc(
            "io.thingsdiary.v1.topic.list",
            request: request,
            response: Io_Thingsdiary_V1_ListTopicsResponse.self
        )
        return ThingsDiaryPage(
            items: response.topics.map(\.wire),
            nextPageToken: response.page.nextPageToken.nilIfEmpty
        )
    }

    public func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        return try decrypt(
            try await encryptedTopic(diaryID: diaryID, topicID: topicID),
            diaryKeys: diaryKeys
        )
    }

    func encryptedTopic(diaryID: String, topicID: String) async throws -> WireTopic {
        var request = Io_Thingsdiary_V1_GetTopicRequest()
        request.diaryID = diaryID
        request.topicID = topicID
        let response = try await rpc(
            "io.thingsdiary.v1.topic.get",
            request: request,
            response: Io_Thingsdiary_V1_GetTopicResponse.self
        )
        return response.topic.wire
    }

    func putEncryptedTopic(
        diaryID: String,
        topicID: String,
        version: UInt64,
        defaultTemplateID: String? = nil,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload
    ) async throws -> WireTopic {
        var request = Io_Thingsdiary_V1_PutTopicRequest()
        request.diaryID = diaryID
        request.topicID = topicID
        request.version = version
        if let defaultTemplateID { request.defaultTemplateID = defaultTemplateID }
        request.encryption = Io_Thingsdiary_V1_Encryption(encryption)
        request.details = Io_Thingsdiary_V1_EncryptedData(details)
        let response = try await rpc(
            "io.thingsdiary.v1.topic.put",
            request: request,
            response: Io_Thingsdiary_V1_PutTopicResponse.self
        )
        return response.topic.wire
    }

    func putPlaintextTopic(
        diaryID: String,
        topicID: String,
        version: UInt64,
        params: ThingsDiaryTopicParams,
        diaryKeys: [ThingsDiaryEncryptionKey]
    ) async throws -> ThingsDiaryTopic {
        guard let activeKey = diaryKeys.first(where: { $0.status == .active }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }
        let entityKey = randomEntryKey()
        let plaintext = try JSONEncoder().encode(TopicDetailsRequest(
            title: params.title,
            description: params.description,
            color: params.color,
            entryPreviewable: params.entryPreviewable
        ))
        let encryptedDetails = try ThingsDiaryCrypto.encrypt(plaintext, key: entityKey)
        let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: activeKey.value)
        let wireTopic = try await putEncryptedTopic(
            diaryID: diaryID,
            topicID: topicID,
            version: version,
            defaultTemplateID: params.defaultTemplateID,
            encryption: ThingsDiaryEntityEncryption(
                diaryKeyID: activeKey.id,
                encryptedKeyNonce: encryptedEntityKey.nonce,
                encryptedKeyData: encryptedEntityKey.ciphertext
            ),
            details: ThingsDiaryEncryptedPayload(
                nonce: encryptedDetails.nonce,
                data: encryptedDetails.ciphertext
            )
        )
        return try decrypt(wireTopic, diaryKeys: diaryKeys)
    }

    public func deleteTopic(
        diaryID: String,
        topicID: String,
        deleteEntries: Bool? = nil,
        soft: Bool? = nil
    ) async throws {
        var request = Io_Thingsdiary_V1_DeleteTopicRequest()
        request.diaryID = diaryID
        request.topicID = topicID
        request.deleteEntries = deleteEntries ?? false
        if let soft { request.soft = soft }
        _ = try await rpc(
            "io.thingsdiary.v1.topic.delete",
            request: request,
            response: Io_Thingsdiary_V1_DeleteTopicResponse.self
        )
    }

    public func restoreTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        var request = Io_Thingsdiary_V1_RestoreTopicRequest()
        request.diaryID = diaryID
        request.topicID = topicID
        let response = try await rpc(
            "io.thingsdiary.v1.topic.restore",
            request: request,
            response: Io_Thingsdiary_V1_RestoreTopicResponse.self
        )
        return try decrypt(response.topic.wire, diaryKeys: diaryKeys)
    }

    func decrypt(
        _ topic: WireTopic,
        diaryKeys: [ThingsDiaryEncryptionKey]
    ) throws -> ThingsDiaryTopic {
        guard let diaryKey = diaryKeys.first(where: { $0.id == topic.encryption.diaryKeyID }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }
        let entityKey = try ThingsDiaryCrypto.decrypt(
            topic.encryption.encryptedKeyData,
            key: diaryKey.value,
            nonce: topic.encryption.encryptedKeyNonce
        )
        let detailsData = try ThingsDiaryCrypto.decrypt(
            topic.details.data,
            key: entityKey,
            nonce: topic.details.nonce
        )
        let details = try JSONDecoder().decode(TopicDetails.self, from: detailsData)
        return ThingsDiaryTopic(
            id: topic.id,
            diaryID: topic.diaryID,
            title: details.title,
            description: details.description ?? "",
            color: details.color,
            entryPreviewable: details.entryPreviewable ?? true,
            defaultTemplateID: topic.defaultTemplateID,
            createdAt: topic.createdAt,
            updatedAt: topic.updatedAt,
            deletedAt: topic.deletedAt,
            version: topic.version
        )
    }
}

private struct TopicDetails: Decodable {
    let title: String
    let description: String?
    let color: String
    let entryPreviewable: Bool?

    enum CodingKeys: String, CodingKey {
        case title, description, color
        case entryPreviewable = "entry_previewable"
    }
}

private struct TopicDetailsRequest: Encodable {
    let title: String
    let description: String
    let color: String
    let entryPreviewable: Bool

    enum CodingKeys: String, CodingKey {
        case title, description, color
        case entryPreviewable = "entry_previewable"
    }
}

private func randomEntryKey() -> Data {
    let key = SymmetricKey(size: .bits256)
    return key.withUnsafeBytes { Data($0) }
}
