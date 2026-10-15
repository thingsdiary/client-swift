import CryptoKit
import Foundation

extension ThingsDiaryClient {
    public func templates(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<ThingsDiaryTemplate> {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let page = try await encryptedTemplates(
            diaryID: diaryID,
            nextPageToken: nextPageToken
        )
        return ThingsDiaryPage(
            items: try page.items.map { try decrypt($0, diaryKeys: diaryKeys) },
            nextPageToken: page.nextPageToken
        )
    }

    public func allTemplates(diaryID: String) async throws -> [ThingsDiaryTemplate] {
        var result: [ThingsDiaryTemplate] = []
        var nextPageToken: String?

        repeat {
            let page = try await templates(
                diaryID: diaryID,
                nextPageToken: nextPageToken
            )
            result.append(contentsOf: page.items)
            nextPageToken = page.nextPageToken
        } while nextPageToken != nil

        return result
    }

    public func createTemplate(
        diaryID: String,
        templateID: String = UUID().uuidString.lowercased(),
        params: ThingsDiaryTemplateParams
    ) async throws -> ThingsDiaryTemplate {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let version = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try await putPlaintextTemplate(
            diaryID: diaryID,
            templateID: templateID,
            version: version,
            params: params,
            diaryKeys: diaryKeys
        )
    }

    public func updateTemplate(
        _ template: ThingsDiaryTemplate,
        params: ThingsDiaryTemplateParams
    ) async throws -> ThingsDiaryTemplate {
        let diaryKeys = try await getDiaryKeys(diaryID: template.diaryID)
        let currentVersion = UInt64(Date().timeIntervalSince1970 * 1_000)
        return try await putPlaintextTemplate(
            diaryID: template.diaryID,
            templateID: template.id,
            version: max(currentVersion, template.version + 1),
            params: params,
            diaryKeys: diaryKeys
        )
    }

    func encryptedTemplates(
        diaryID: String,
        nextPageToken: String? = nil
    ) async throws -> ThingsDiaryPage<WireTemplate> {
        var query: [URLQueryItem] = []
        if let nextPageToken {
            query.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
        }
        let response: TemplatesResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates"],
            method: "GET",
            query: query
        )
        return ThingsDiaryPage(items: response.templates, nextPageToken: response.nextPageToken)
    }

    public func getTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        return try decrypt(
            try await encryptedTemplate(diaryID: diaryID, templateID: templateID),
            diaryKeys: diaryKeys
        )
    }

    func encryptedTemplate(diaryID: String, templateID: String) async throws -> WireTemplate {
        let response: TemplateResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates", templateID],
            method: "GET"
        )
        return response.template
    }

    func putEncryptedTemplate(
        diaryID: String,
        templateID: String,
        version: UInt64,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload
    ) async throws -> WireTemplate {
        let body = try JSONEncoder().encode(PutTemplateBody(
            version: version,
            encryption: encryption,
            details: details
        ))
        let response: TemplateResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates", templateID],
            method: "PUT",
            body: body,
            signed: true
        )
        return response.template
    }

    func putPlaintextTemplate(
        diaryID: String,
        templateID: String,
        version: UInt64,
        params: ThingsDiaryTemplateParams,
        diaryKeys: [ThingsDiaryEncryptionKey]
    ) async throws -> ThingsDiaryTemplate {
        guard let activeKey = diaryKeys.first(where: { $0.status == .active }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }
        let entityKey = randomEntryKey()
        let plaintext = try JSONEncoder().encode(TemplateDetailsRequest(content: params.content))
        let details = try ThingsDiaryCrypto.encrypt(plaintext, key: entityKey)
        let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: activeKey.value)
        let wireTemplate = try await putEncryptedTemplate(
            diaryID: diaryID,
            templateID: templateID,
            version: version,
            encryption: ThingsDiaryEntityEncryption(
                diaryKeyID: activeKey.id,
                encryptedKeyNonce: encryptedEntityKey.nonce,
                encryptedKeyData: encryptedEntityKey.ciphertext
            ),
            details: ThingsDiaryEncryptedPayload(
                nonce: details.nonce,
                data: details.ciphertext
            )
        )
        return try decrypt(wireTemplate, diaryKeys: diaryKeys)
    }

    public func deleteTemplate(
        diaryID: String,
        templateID: String,
        soft: Bool? = nil
    ) async throws {
        var query: [URLQueryItem] = []
        if let soft {
            query.append(URLQueryItem(name: "soft", value: soft ? "true" : "false"))
        }
        try await sendEntityNoContent(
            path: ["v1", "diaries", diaryID, "templates", templateID],
            method: "DELETE",
            query: query
        )
    }

    public func restoreTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        let response: TemplateResponse = try await sendEntityRequest(
            path: ["v1", "diaries", diaryID, "templates", templateID, "restore"],
            method: "POST"
        )
        return try decrypt(response.template, diaryKeys: diaryKeys)
    }

    func decrypt(
        _ template: WireTemplate,
        diaryKeys: [ThingsDiaryEncryptionKey]
    ) throws -> ThingsDiaryTemplate {
        guard let diaryKey = diaryKeys.first(where: {
            $0.id == template.encryption.diaryKeyID
        }) else {
            throw ThingsDiaryClientError.missingActiveEncryptionKey
        }
        let entityKey = try ThingsDiaryCrypto.decrypt(
            template.encryption.encryptedKeyData,
            key: diaryKey.value,
            nonce: template.encryption.encryptedKeyNonce
        )
        let detailsData = try ThingsDiaryCrypto.decrypt(
            template.details.data,
            key: entityKey,
            nonce: template.details.nonce
        )
        let details = try JSONDecoder().decode(TemplateDetails.self, from: detailsData)
        return ThingsDiaryTemplate(
            id: template.id,
            diaryID: template.diaryID,
            content: details.content,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt,
            deletedAt: template.deletedAt,
            version: template.version
        )
    }
}

private struct PutTemplateBody: Encodable {
    let version: UInt64
    let encryption: ThingsDiaryEntityEncryption
    let details: ThingsDiaryEncryptedPayload
}

private struct TemplateResponse: Decodable {
    let template: WireTemplate
}

private struct TemplatesResponse: Decodable {
    let templates: [WireTemplate]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case templates
        case nextPageToken = "next_page_token"
    }
}

private struct TemplateDetails: Decodable {
    let content: String
}

private struct TemplateDetailsRequest: Encodable {
    let content: String
}

private func randomEntryKey() -> Data {
    let key = SymmetricKey(size: .bits256)
    return key.withUnsafeBytes { Data($0) }
}
