import Foundation

extension ThingsDiaryClient {
    public func templates(diaryID: String, nextPageToken: String? = nil) async throws -> ThingsDiaryPage<ThingsDiaryTemplate> {
        var query: [URLQueryItem] = []
        if let nextPageToken { query.append(URLQueryItem(name: "next_page_token", value: nextPageToken)) }
        let response: TemplatesResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates"], method: "GET", query: query
        )
        return ThingsDiaryPage(items: response.templates, nextPageToken: response.nextPageToken)
    }

    public func getTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
        let response: TemplateResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates", templateID], method: "GET"
        )
        return response.template
    }

    public func putTemplate(
        diaryID: String,
        templateID: String,
        version: UInt64,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload
    ) async throws -> ThingsDiaryTemplate {
        let body = try JSONEncoder().encode(PutTemplateBody(version: version, encryption: encryption, details: details))
        let response: TemplateResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates", templateID], method: "PUT", body: body, signed: true
        )
        return response.template
    }

    public func deleteTemplate(diaryID: String, templateID: String, soft: Bool? = nil) async throws {
        var query: [URLQueryItem] = []
        if let soft { query.append(URLQueryItem(name: "soft", value: soft ? "true" : "false")) }
        try await sendEntityNoContent(path: ["v1", "diaries", diaryID, "templates", templateID], method: "DELETE", query: query)
    }

    public func restoreTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
        let response: TemplateResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates", templateID, "restore"], method: "POST"
        )
        return response.template
    }
}

private struct PutTemplateBody: Encodable {
    let version: UInt64
    let encryption: ThingsDiaryEntityEncryption
    let details: ThingsDiaryEncryptedPayload
}

private struct TemplateResponse: Decodable { let template: ThingsDiaryTemplate }
private struct TemplatesResponse: Decodable {
    let templates: [ThingsDiaryTemplate]
    let nextPageToken: String?
    enum CodingKeys: String, CodingKey { case templates; case nextPageToken = "next_page_token" }
}
