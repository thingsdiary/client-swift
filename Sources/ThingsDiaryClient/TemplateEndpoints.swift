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
        var request = Io_Thingsdiary_V1_ListTemplatesRequest()
        request.diaryID = diaryID
        request.page.pageToken = nextPageToken ?? ""
        let response = try await rpc(
            "io.thingsdiary.v1.template.list",
            request: request,
            response: Io_Thingsdiary_V1_ListTemplatesResponse.self
        )
        return ThingsDiaryPage(
            items: response.templates.map(\.wire),
            nextPageToken: response.page.nextPageToken.nilIfEmpty
        )
    }

    public func getTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        return try decrypt(
            try await encryptedTemplate(diaryID: diaryID, templateID: templateID),
            diaryKeys: diaryKeys
        )
    }

    func encryptedTemplate(diaryID: String, templateID: String) async throws -> WireTemplate {
        var request = Io_Thingsdiary_V1_GetTemplateRequest()
        request.diaryID = diaryID
        request.templateID = templateID
        let response = try await rpc(
            "io.thingsdiary.v1.template.get",
            request: request,
            response: Io_Thingsdiary_V1_GetTemplateResponse.self
        )
        return response.template.wire
    }

    func putEncryptedTemplate(
        diaryID: String,
        templateID: String,
        version: UInt64,
        encryption: ThingsDiaryEntityEncryption,
        details: ThingsDiaryEncryptedPayload
    ) async throws -> WireTemplate {
        var request = Io_Thingsdiary_V1_PutTemplateRequest()
        request.diaryID = diaryID
        request.templateID = templateID
        request.version = version
        request.encryption = Io_Thingsdiary_V1_Encryption(encryption)
        request.details = Io_Thingsdiary_V1_EncryptedData(details)
        let response = try await rpc(
            "io.thingsdiary.v1.template.put",
            request: request,
            response: Io_Thingsdiary_V1_PutTemplateResponse.self
        )
        return response.template.wire
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
        var request = Io_Thingsdiary_V1_DeleteTemplateRequest()
        request.diaryID = diaryID
        request.templateID = templateID
        if let soft { request.soft = soft }
        _ = try await rpc(
            "io.thingsdiary.v1.template.delete",
            request: request,
            response: Io_Thingsdiary_V1_DeleteTemplateResponse.self
        )
    }

    public func restoreTemplate(diaryID: String, templateID: String) async throws -> ThingsDiaryTemplate {
        let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
        var request = Io_Thingsdiary_V1_RestoreTemplateRequest()
        request.diaryID = diaryID
        request.templateID = templateID
        let response = try await rpc(
            "io.thingsdiary.v1.template.restore",
            request: request,
            response: Io_Thingsdiary_V1_RestoreTemplateResponse.self
        )
        return try decrypt(response.template.wire, diaryKeys: diaryKeys)
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
