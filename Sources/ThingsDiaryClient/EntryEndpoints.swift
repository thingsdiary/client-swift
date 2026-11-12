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
    return try await putPlaintextEntry(
      diaryID: diaryID,
      entryID: entryID,
      parentChangeIDs: [],
      params: params,
      diaryKeys: diaryKeys
    )
  }

  public func updateEntry(
    _ entry: ThingsDiaryEntry,
    params: ThingsDiaryEntryParams
  ) async throws -> ThingsDiaryEntry {
    let diaryKeys = try await getDiaryKeys(diaryID: entry.diaryID)
    let current = try await encryptedEntry(diaryID: entry.diaryID, entryID: entry.id)
    return try await putPlaintextEntry(
      diaryID: entry.diaryID,
      entryID: entry.id,
      parentChangeIDs: [current.change.change.id],
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
    topicID: String? = nil,
    encryptedChange: Io_Thingsdiary_V1_EncryptedChange
  ) async throws -> WireEntry {
    var request = Io_Thingsdiary_V1_PutEntryRequest()
    request.diaryID = diaryID
    request.entryID = entryID
    if let topicID { request.topicID = topicID }
    request.encryptedChange = encryptedChange
    let response = try await rpc(
      "io.thingsdiary.v1.entry.put",
      request: request,
      response: Io_Thingsdiary_V1_PutEntryResponse.self
    )
    try checkEntryError(response.errorCode)
    return response.entry.wire
  }

  func putPlaintextEntry(
    diaryID: String,
    entryID: String,
    parentChangeIDs: [String],
    params: ThingsDiaryEntryParams,
    diaryKeys: [ThingsDiaryEncryptionKey]
  ) async throws -> ThingsDiaryEntry {
    guard let activeKey = diaryKeys.first(where: { $0.status == .active }) else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let entityKey = randomEntryKey()
    var payload = Io_Thingsdiary_V1_EntryDetails()
    payload.content = params.content
    payload.archived = params.archived
    payload.bookmarked = params.bookmarked
    payload.previewHidden = params.previewHidden
    let details = try ThingsDiaryCrypto.encrypt(payload.serializedData(), key: entityKey)
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(
      entityKey,
      key: activeKey.value
    )
    var change = Io_Thingsdiary_V1_Change()
    change.id = UUID().uuidString.lowercased()
    if !parentChangeIDs.isEmpty { change.objectID = entryID }
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
    let wireEntry = try await putEncryptedEntry(
      diaryID: diaryID,
      entryID: entryID,
      topicID: params.topicID,
      encryptedChange: encryptedChange
    )
    return try decrypt(wireEntry, diaryKeys: diaryKeys)
  }

  public func deleteEntry(
    diaryID: String,
    entryID: String,
    soft: Bool? = nil
  ) async throws {
    let entry = try await encryptedEntry(diaryID: diaryID, entryID: entryID)
    var request = Io_Thingsdiary_V1_DeleteEntryRequest()
    request.diaryID = diaryID
    request.entryID = entryID
    if let soft { request.soft = soft }
    request.encryptedChange = stateChange(for: entry)
    let response = try await rpc(
      "io.thingsdiary.v1.entry.delete",
      request: request,
      response: Io_Thingsdiary_V1_DeleteEntryResponse.self
    )
    try checkEntryError(response.errorCode)
  }

  public func restoreEntry(diaryID: String, entryID: String) async throws -> ThingsDiaryEntry {
    let diaryKeys = try await getDiaryKeys(diaryID: diaryID)
    let entry = try await encryptedEntry(diaryID: diaryID, entryID: entryID)
    var request = Io_Thingsdiary_V1_RestoreEntryRequest()
    request.diaryID = diaryID
    request.entryID = entryID
    request.encryptedChange = stateChange(for: entry)
    let response = try await rpc(
      "io.thingsdiary.v1.entry.restore",
      request: request,
      response: Io_Thingsdiary_V1_RestoreEntryResponse.self
    )
    try checkEntryError(response.errorCode)
    return try decrypt(response.entry.wire, diaryKeys: diaryKeys)
  }

  func decrypt(
    _ entry: WireEntry,
    diaryKeys: [ThingsDiaryEncryptionKey]
  ) throws -> ThingsDiaryEntry {
    guard
      let diaryKey = diaryKeys.first(where: {
        $0.id == entry.change.encryption.diaryKeyID
      })
    else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let entityKey = try ThingsDiaryCrypto.decrypt(
      entry.change.encryption.encryptedKeyData,
      key: diaryKey.value,
      nonce: entry.change.encryption.encryptedKeyNonce
    )
    let encryptedPayload = try Io_Thingsdiary_V1_EncryptedData(
      serializedBytes: entry.change.change.payload
    )
    let detailsData = try ThingsDiaryCrypto.decrypt(
      encryptedPayload.data,
      key: entityKey,
      nonce: encryptedPayload.nonce
    )
    let details = try Io_Thingsdiary_V1_EntryDetails(serializedBytes: detailsData)
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
      removedAt: entry.removedAt
    )
  }

}

private func stateChange(for entry: WireEntry) -> Io_Thingsdiary_V1_EncryptedChange {
  var change = Io_Thingsdiary_V1_Change()
  change.id = UUID().uuidString.lowercased()
  change.objectID = entry.id
  change.parentChangeIds = [entry.change.change.id]
  change.payload = entry.change.change.payload

  var encryptedChange = Io_Thingsdiary_V1_EncryptedChange()
  encryptedChange.change = change
  encryptedChange.encryption = Io_Thingsdiary_V1_Encryption(entry.change.encryption)
  return encryptedChange
}

private func checkEntryError(_ errorCode: Io_Thingsdiary_V1_ErrorCode) throws {
  guard errorCode == .unspecified else {
    throw ThingsDiaryClientError.apiError(errorCode.rawValue)
  }
}

private func randomEntryKey() -> Data {
  let key = SymmetricKey(size: .bits256)
  return key.withUnsafeBytes { Data($0) }
}
