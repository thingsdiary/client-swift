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
    return try await putPlaintextTopic(
      diaryID: diaryID,
      topicID: topicID,
      parentChangeIDs: [],
      params: params,
      diaryKeys: diaryKeys
    )
  }

  public func updateTopic(
    _ topic: ThingsDiaryTopic,
    params: ThingsDiaryTopicParams
  ) async throws -> ThingsDiaryTopic {
    let diaryKeys = try await getDiaryKeys(diaryID: topic.diaryID)
    let current = try await encryptedTopic(diaryID: topic.diaryID, topicID: topic.id)
    return try await putPlaintextTopic(
      diaryID: topic.diaryID,
      topicID: topic.id,
      parentChangeIDs: [current.change.change.id],
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
    defaultTemplateID: String? = nil,
    encryptedChange: Io_Thingsdiary_V1_EncryptedChange
  ) async throws -> WireTopic {
    var request = Io_Thingsdiary_V1_PutTopicRequest()
    request.diaryID = diaryID
    request.topicID = topicID
    if let defaultTemplateID { request.defaultTemplateID = defaultTemplateID }
    request.encryptedChange = encryptedChange
    let response = try await rpc(
      "io.thingsdiary.v1.topic.put",
      request: request,
      response: Io_Thingsdiary_V1_PutTopicResponse.self
    )
    try checkTopicError(response.errorCode)
    return response.topic.wire
  }

  func putPlaintextTopic(
    diaryID: String,
    topicID: String,
    parentChangeIDs: [String],
    params: ThingsDiaryTopicParams,
    diaryKeys: [ThingsDiaryEncryptionKey]
  ) async throws -> ThingsDiaryTopic {
    guard let activeKey = diaryKeys.first(where: { $0.status == .active }) else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let entityKey = randomEntryKey()
    var payload = Io_Thingsdiary_V1_TopicDetails()
    payload.title = params.title
    payload.description_p = params.description
    payload.color = params.color
    payload.entryPreviewable = params.entryPreviewable
    let plaintext = try payload.serializedData()
    let encryptedDetails = try ThingsDiaryCrypto.encrypt(plaintext, key: entityKey)
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: activeKey.value)
    var change = Io_Thingsdiary_V1_Change()
    change.id = UUID().uuidString.lowercased()
    if !parentChangeIDs.isEmpty { change.objectID = topicID }
    change.parentChangeIds = parentChangeIDs
    change.payload = try Io_Thingsdiary_V1_EncryptedData(
      ThingsDiaryEncryptedPayload(
        nonce: encryptedDetails.nonce,
        data: encryptedDetails.ciphertext
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
    let wireTopic = try await putEncryptedTopic(
      diaryID: diaryID,
      topicID: topicID,
      defaultTemplateID: params.defaultTemplateID,
      encryptedChange: encryptedChange
    )
    return try decrypt(wireTopic, diaryKeys: diaryKeys)
  }

  public func deleteTopic(
    diaryID: String,
    topicID: String,
    deleteEntries: Bool? = nil,
    soft: Bool? = nil
  ) async throws {
    let topic = try await encryptedTopic(diaryID: diaryID, topicID: topicID)
    var request = Io_Thingsdiary_V1_DeleteTopicRequest()
    request.diaryID = diaryID
    request.topicID = topicID
    request.deleteEntries = deleteEntries ?? false
    if let soft { request.soft = soft }
    request.encryptedChange = topicStateChange(for: topic)
    let response = try await rpc(
      "io.thingsdiary.v1.topic.delete",
      request: request,
      response: Io_Thingsdiary_V1_DeleteTopicResponse.self
    )
    try checkTopicError(response.errorCode)
  }

  public func restoreTopic(diaryID: String, topicID: String) async throws -> ThingsDiaryTopic {
    let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
    let topic = try await encryptedTopic(diaryID: diaryID, topicID: topicID)
    var request = Io_Thingsdiary_V1_RestoreTopicRequest()
    request.diaryID = diaryID
    request.topicID = topicID
    request.encryptedChange = topicStateChange(for: topic)
    let response = try await rpc(
      "io.thingsdiary.v1.topic.restore",
      request: request,
      response: Io_Thingsdiary_V1_RestoreTopicResponse.self
    )
    try checkTopicError(response.errorCode)
    return try decrypt(response.topic.wire, diaryKeys: diaryKeys)
  }

  func decrypt(
    _ topic: WireTopic,
    diaryKeys: [ThingsDiaryEncryptionKey]
  ) throws -> ThingsDiaryTopic {
    guard let diaryKey = diaryKeys.first(where: {
      $0.id == topic.change.encryption.diaryKeyID
    }) else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let entityKey = try ThingsDiaryCrypto.decrypt(
      topic.change.encryption.encryptedKeyData,
      key: diaryKey.value,
      nonce: topic.change.encryption.encryptedKeyNonce
    )
    let encryptedPayload = try Io_Thingsdiary_V1_EncryptedData(
      serializedBytes: topic.change.change.payload
    )
    let detailsData = try ThingsDiaryCrypto.decrypt(
      encryptedPayload.data,
      key: entityKey,
      nonce: encryptedPayload.nonce
    )
    let details = try Io_Thingsdiary_V1_TopicDetails(serializedBytes: detailsData)
    return ThingsDiaryTopic(
      id: topic.id,
      diaryID: topic.diaryID,
      title: details.title,
      description: details.description_p,
      color: details.color,
      entryPreviewable: details.hasEntryPreviewable ? details.entryPreviewable : true,
      defaultTemplateID: topic.defaultTemplateID,
      createdAt: topic.createdAt,
      updatedAt: topic.updatedAt,
      deletedAt: topic.deletedAt,
      removedAt: topic.removedAt
    )
  }
}

private func topicStateChange(for topic: WireTopic) -> Io_Thingsdiary_V1_EncryptedChange {
  var change = Io_Thingsdiary_V1_Change()
  change.id = UUID().uuidString.lowercased()
  change.objectID = topic.id
  change.parentChangeIds = [topic.change.change.id]
  change.payload = topic.change.change.payload

  var encryptedChange = Io_Thingsdiary_V1_EncryptedChange()
  encryptedChange.change = change
  encryptedChange.encryption = Io_Thingsdiary_V1_Encryption(topic.change.encryption)
  return encryptedChange
}

private func checkTopicError(_ errorCode: Io_Thingsdiary_V1_ErrorCode) throws {
  guard errorCode == .unspecified else {
    throw ThingsDiaryClientError.apiError(errorCode.rawValue)
  }
}

private func randomEntryKey() -> Data {
  let key = SymmetricKey(size: .bits256)
  return key.withUnsafeBytes { Data($0) }
}
