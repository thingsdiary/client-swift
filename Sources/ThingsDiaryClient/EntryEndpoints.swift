import Foundation

extension ThingsDiaryClient {
    public func entries(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<ThingsDiaryEntry> {
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
        let response: EntryResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "entries", entryID],
            method: "GET"
        )
        return response.entry
    }

    public func putEntry(
        diaryID: String,
        entryID: String,
        version: UInt64,
        topicID: String? = nil,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload,
        preview: ThingsDiaryEncryptedPayload
    ) async throws -> ThingsDiaryEntry {
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
        let response: EntryResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "entries", entryID, "restore"],
            method: "POST"
        )
        return response.entry
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
    let entry: ThingsDiaryEntry
}

private struct EntriesResponse: Decodable {
    let entries: [ThingsDiaryEntry]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case nextPageToken = "next_page_token"
    }
}
