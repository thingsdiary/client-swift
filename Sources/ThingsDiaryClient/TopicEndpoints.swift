import Foundation

extension ThingsDiaryClient {
    public func topics(diaryID: String, nextPageToken: String? = nil) async throws -> ThingsDiaryPage<ThingsDiaryTopic> {
        var query: [URLQueryItem] = []
        if let nextPageToken { query.append(URLQueryItem(name: "next_page_token", value: nextPageToken)) }
        let response: TopicsResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics"], method: "GET", query: query
        )
        return ThingsDiaryPage(items: response.topics, nextPageToken: response.nextPageToken)
    }

    public func getTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
        let response: TopicResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics", topicID], method: "GET"
        )
        return response.topic
    }

    public func putTopic(
        diaryID: String,
        topicID: String,
        version: UInt64,
        defaultTemplateID: String? = nil,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload
    ) async throws -> ThingsDiaryTopic {
        let body = try JSONEncoder().encode(PutTopicBody(
            version: version, defaultTemplateID: defaultTemplateID, encryption: encryption, details: details
        ))
        let response: TopicResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics", topicID], method: "PUT", body: body, signed: true
        )
        return response.topic
    }

    public func deleteTopic(
        diaryID: String,
        topicID: String,
        deleteEntries: Bool? = nil,
        soft: Bool? = nil
    ) async throws {
        var query: [URLQueryItem] = []
        if let deleteEntries { query.append(URLQueryItem(name: "delete_entries", value: deleteEntries ? "true" : "false")) }
        if let soft { query.append(URLQueryItem(name: "soft", value: soft ? "true" : "false")) }
        try await sendEntityNoContent(path: ["v1", "diaries", diaryID, "topics", topicID], method: "DELETE", query: query)
    }

    public func restoreTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
        let response: TopicResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "topics", topicID, "restore"], method: "POST"
        )
        return response.topic
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

private struct TopicResponse: Decodable { let topic: ThingsDiaryTopic }
private struct TopicsResponse: Decodable {
    let topics: [ThingsDiaryTopic]
    let nextPageToken: String?
    enum CodingKeys: String, CodingKey { case topics; case nextPageToken = "next_page_token" }
}
