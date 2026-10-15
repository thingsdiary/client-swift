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
        var query: [URLQueryItem] = []
        if let nextPageToken {
            query.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
        }
        let response: TopicsResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics"],
            method: "GET",
            query: query
        )
        return ThingsDiaryPage(items: response.topics, nextPageToken: response.nextPageToken)
    }

    public func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        return try decrypt(
            try await encryptedTopic(diaryID: diaryID, topicID: topicID),
            diaryKeys: diaryKeys
        )
    }

    func encryptedTopic(diaryID: String, topicID: String) async throws -> WireTopic {
        let response: TopicResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics", topicID],
            method: "GET"
        )
        return response.topic
    }

    func putEncryptedTopic(
        diaryID: String,
        topicID: String,
        version: UInt64,
        defaultTemplateID: String? = nil,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload
    ) async throws -> WireTopic {
        let body = try JSONEncoder().encode(PutTopicBody(
            version: version,
            defaultTemplateID: defaultTemplateID,
            encryption: encryption,
            details: details
        ))
        let response: TopicResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics", topicID],
            method: "PUT",
            body: body,
            signed: true
        )
        return response.topic
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
        var query: [URLQueryItem] = []
        if let deleteEntries {
            query.append(URLQueryItem(name: "delete_entries", value: deleteEntries ? "true" : "false"))
        }
        if let soft {
            query.append(URLQueryItem(name: "soft", value: soft ? "true" : "false"))
        }
        try await sendEntityNoContent(
            path: ["v1", "diaries", diaryID, "topics", topicID],
            method: "DELETE",
            query: query
        )
    }

    public func restoreTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let response: TopicResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics", topicID, "restore"],
            method: "POST"
        )
        return try decrypt(response.topic, diaryKeys: diaryKeys)
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

private struct PutTopicBody: Encodable {
    let version: UInt64
    let defaultTemplateID: String?
    let encryption: ThingsDiaryEntityEncryption
    let details: ThingsDiaryEncryptedPayload

    enum CodingKeys: String, CodingKey {
        case version, encryption, details
        case defaultTemplateID = "default_template_id"
    }
}

private struct TopicResponse: Decodable { let topic: WireTopic }

private struct TopicsResponse: Decodable {
    let topics: [WireTopic]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case topics
        case nextPageToken = "next_page_token"
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
