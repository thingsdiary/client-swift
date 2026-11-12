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
    return try await putPlaintextTemplate(
      diaryID: diaryID,
      templateID: templateID,
      parentChangeIDs: [],
      params: params,
      diaryKeys: diaryKeys
    )
  }

  public func updateTemplate(
    _ template: ThingsDiaryTemplate,
    params: ThingsDiaryTemplateParams
  ) async throws -> ThingsDiaryTemplate {
    let diaryKeys = try await getDiaryKeys(diaryID: template.diaryID)
    let current = try await encryptedTemplate(diaryID: template.diaryID, templateID: template.id)
    return try await putPlaintextTemplate(
      diaryID: template.diaryID,
      templateID: template.id,
      parentChangeIDs: [current.change.change.id],
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
    encryptedChange: Io_Thingsdiary_V1_EncryptedChange
  ) async throws -> WireTemplate {
    var request = Io_Thingsdiary_V1_PutTemplateRequest()
    request.diaryID = diaryID
    request.templateID = templateID
    request.encryptedChange = encryptedChange
    let response = try await rpc(
      "io.thingsdiary.v1.template.put",
      request: request,
      response: Io_Thingsdiary_V1_PutTemplateResponse.self
    )
    try checkTemplateError(response.errorCode)
    return response.template.wire
  }

  func putPlaintextTemplate(
    diaryID: String,
    templateID: String,
    parentChangeIDs: [String],
    params: ThingsDiaryTemplateParams,
    diaryKeys: [ThingsDiaryEncryptionKey]
  ) async throws -> ThingsDiaryTemplate {
    guard let activeKey = diaryKeys.first(where: { $0.status == .active }) else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let entityKey = randomEntryKey()
    var payload = Io_Thingsdiary_V1_TemplateDetails()
    payload.content = params.content
    let plaintext = try payload.serializedData()
    let details = try ThingsDiaryCrypto.encrypt(plaintext, key: entityKey)
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: activeKey.value)
    var change = Io_Thingsdiary_V1_Change()
    change.id = UUID().uuidString.lowercased()
    if !parentChangeIDs.isEmpty { change.objectID = templateID }
    change.parentChangeIds = parentChangeIDs
    change.payload = try Io_Thingsdiary_V1_EncryptedData(
      ThingsDiaryEncryptedPayload(
        nonce: details.nonce,
        data: details.ciphertext
      )
    ).serializedData()
    var encryptedChange = Io_Thingsdiary_V1_EncryptedChange()
    encryptedChange.change = change
    encryptedChange.encryption = Io_Thingsdiary_V1_Encryption(
      ThingsDiaryEntityEncryption(
        diaryKeyID: activeKey.id,
        encryptedKeyNonce: encryptedEntityKey.nonce,
        encryptedKeyData: encryptedEntityKey.ciphertext
      )
    )
    let wireTemplate = try await putEncryptedTemplate(
      diaryID: diaryID,
      templateID: templateID,
      encryptedChange: encryptedChange
    )
    return try decrypt(wireTemplate, diaryKeys: diaryKeys)
  }

  public func deleteTemplate(
    diaryID: String,
    templateID: String,
    soft: Bool? = nil
  ) async throws {
    let template = try await encryptedTemplate(diaryID: diaryID, templateID: templateID)
    var request = Io_Thingsdiary_V1_DeleteTemplateRequest()
    request.diaryID = diaryID
    request.templateID = templateID
    if let soft { request.soft = soft }
    request.encryptedChange = templateStateChange(for: template)
    let response = try await rpc(
      "io.thingsdiary.v1.template.delete",
      request: request,
      response: Io_Thingsdiary_V1_DeleteTemplateResponse.self
    )
    try checkTemplateError(response.errorCode)
  }

  public func restoreTemplate(diaryID: String, templateID: String) async throws
    -> ThingsDiaryTemplate
  {
    let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
    let template = try await encryptedTemplate(diaryID: diaryID, templateID: templateID)
    var request = Io_Thingsdiary_V1_RestoreTemplateRequest()
    request.diaryID = diaryID
    request.templateID = templateID
    request.encryptedChange = templateStateChange(for: template)
    let response = try await rpc(
      "io.thingsdiary.v1.template.restore",
      request: request,
      response: Io_Thingsdiary_V1_RestoreTemplateResponse.self
    )
    try checkTemplateError(response.errorCode)
    return try decrypt(response.template.wire, diaryKeys: diaryKeys)
  }

  func decrypt(
    _ template: WireTemplate,
    diaryKeys: [ThingsDiaryEncryptionKey]
  ) throws -> ThingsDiaryTemplate {
    guard
      let diaryKey = diaryKeys.first(where: {
        $0.id == template.change.encryption.diaryKeyID
      })
    else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let entityKey = try ThingsDiaryCrypto.decrypt(
      template.change.encryption.encryptedKeyData,
      key: diaryKey.value,
      nonce: template.change.encryption.encryptedKeyNonce
    )
    let encryptedPayload = try Io_Thingsdiary_V1_EncryptedData(
      serializedBytes: template.change.change.payload
    )
    let detailsData = try ThingsDiaryCrypto.decrypt(
      encryptedPayload.data,
      key: entityKey,
      nonce: encryptedPayload.nonce
    )
    let details = try Io_Thingsdiary_V1_TemplateDetails(serializedBytes: detailsData)
    return ThingsDiaryTemplate(
      id: template.id,
      diaryID: template.diaryID,
      content: details.content,
      createdAt: template.createdAt,
      updatedAt: template.updatedAt,
      deletedAt: template.deletedAt,
      removedAt: template.removedAt
    )
  }
}

private func templateStateChange(for template: WireTemplate) -> Io_Thingsdiary_V1_EncryptedChange {
  var change = Io_Thingsdiary_V1_Change()
  change.id = UUID().uuidString.lowercased()
  change.objectID = template.id
  change.parentChangeIds = [template.change.change.id]
  change.payload = template.change.change.payload

  var encryptedChange = Io_Thingsdiary_V1_EncryptedChange()
  encryptedChange.change = change
  encryptedChange.encryption = Io_Thingsdiary_V1_Encryption(template.change.encryption)
  return encryptedChange
}

private func checkTemplateError(_ errorCode: Io_Thingsdiary_V1_ErrorCode) throws {
  guard errorCode == .unspecified else {
    throw ThingsDiaryClientError.apiError(errorCode.rawValue)
  }
}

private func randomEntryKey() -> Data {
  let key = SymmetricKey(size: .bits256)
  return key.withUnsafeBytes { Data($0) }
}
