import CryptoKit
import Foundation

extension ThingsDiaryClient {
  public func createDiary(_ params: ThingsDiaryCreateParams) async throws -> ThingsDiaryDiary {
    guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }

    let diaryKey = randomSymmetricKey()
    let entityKey = randomSymmetricKey()
    let details = try encodeDetails(title: params.title, description: params.description)
    let encryptedDetails = try ThingsDiaryCrypto.encrypt(details, key: entityKey)
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: diaryKey)
    let sealedDiaryKey = try ThingsDiaryCrypto.seal(
      diaryKey,
      recipientPublicKey: authentication.credentials.encryptionPublicKey
    )
    var change = Io_Thingsdiary_V1_Change()
    change.id = UUID().uuidString
    change.payload = try Io_Thingsdiary_V1_EncryptedData(
      ThingsDiaryEncryptedPayload(nonce: encryptedDetails.nonce, data: encryptedDetails.ciphertext)
    ).serializedData()
    var encryptedChange = Io_Thingsdiary_V1_EncryptedChange()
    encryptedChange.change = change
    encryptedChange.encryption = Io_Thingsdiary_V1_Encryption(
      ThingsDiaryEntityEncryption(
        diaryKeyID: "",
        encryptedKeyNonce: encryptedEntityKey.nonce,
        encryptedKeyData: encryptedEntityKey.ciphertext
      )
    )
    var request = Io_Thingsdiary_V1_CreateDiaryRequest()
    request.encryptedDiaryKey = sealedDiaryKey
    request.encryptedChange = encryptedChange
    let response = try await rpc(
      "io.thingsdiary.v1.diary.create",
      request: request,
      response: Io_Thingsdiary_V1_CreateDiaryResponse.self
    )
    return try await getDiary(id: response.diaryID)
  }

  public func createDiary(title: String, description: String) async throws -> ThingsDiaryDiary {
    try await createDiary(ThingsDiaryCreateParams(title: title, description: description))
  }

  public func putDiary(id: String, params: ThingsDiaryPutParams) async throws -> ThingsDiaryDiary {
    guard authentication != nil else { throw ThingsDiaryClientError.notAuthenticated }
    var getRequest = Io_Thingsdiary_V1_GetDiaryRequest()
    getRequest.diaryID = id
    let currentResponse = try await rpc(
      "io.thingsdiary.v1.diary.get",
      request: getRequest,
      response: Io_Thingsdiary_V1_GetDiaryResponse.self
    )
    let currentDiary = currentResponse.diary
    guard let activeKey = currentDiary.encryptionKeys.first(where: { $0.status == .active })
      ?? currentDiary.encryptionKeys.first
    else { throw ThingsDiaryClientError.missingActiveEncryptionKey }

    let entityKey = randomSymmetricKey()
    let details = try encodeDetails(title: params.title, description: params.description)
    let encryptedDetails = try ThingsDiaryCrypto.encrypt(details, key: entityKey)
    let encryptedEntityKey = try ThingsDiaryCrypto.encrypt(entityKey, key: activeKey.value)
    var change = Io_Thingsdiary_V1_Change()
    change.id = UUID().uuidString
    change.objectID = id
    change.parentChangeIds = currentDiary.hasChange ? [currentDiary.change.change.id] : []
    change.payload = try Io_Thingsdiary_V1_EncryptedData(
      ThingsDiaryEncryptedPayload(nonce: encryptedDetails.nonce, data: encryptedDetails.ciphertext)
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
    var request = Io_Thingsdiary_V1_PutDiaryRequest()
    request.diaryID = id
    request.encryptedChange = encryptedChange
    _ = try await rpc(
      "io.thingsdiary.v1.diary.put",
      request: request,
      response: Io_Thingsdiary_V1_PutDiaryResponse.self
    )
    return try await getDiary(id: id)
  }

  public func updateDiary(id: String, params: ThingsDiaryPutParams) async throws -> ThingsDiaryDiary
  {
    try await putDiary(id: id, params: params)
  }

  public func updateDiary(
    _ diary: ThingsDiaryDiary,
    params: ThingsDiaryDiaryParams
  ) async throws -> ThingsDiaryDiary {
    let currentVersion = UInt64(Date().timeIntervalSince1970 * 1_000)
    return try await putDiary(
      id: diary.id,
      params: ThingsDiaryPutParams(
        title: params.title,
        description: params.description,
        version: max(currentVersion, diary.version + 1)
      )
    )
  }

  public func deleteDiary(id: String) async throws {
    var request = Io_Thingsdiary_V1_DeleteDiaryRequest()
    request.diaryID = id
    _ = try await rpc(
      "io.thingsdiary.v1.diary.delete",
      request: request,
      response: Io_Thingsdiary_V1_DeleteDiaryResponse.self
    )
  }

  public func getDiaryKeys(diaryID: String) async throws -> [ThingsDiaryEncryptionKey] {
    guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }
    var request = Io_Thingsdiary_V1_ListDiaryKeysRequest()
    request.diaryID = diaryID
    let response = try await rpc(
      "io.thingsdiary.v1.diary_key.list",
      request: request,
      response: Io_Thingsdiary_V1_ListDiaryKeysResponse.self
    )
    return try response.keys.map { key in
      let openedKey = try ThingsDiaryCrypto.openSealedBox(
        key.value,
        recipientPrivateKey: authentication.credentials.encryptionPrivateKey,
        recipientPublicKey: authentication.credentials.encryptionPublicKey
      )
      let status: ThingsDiaryEncryptionKeyStatus
      switch key.status {
      case .active: status = .active
      case .rotated: status = .rotated
      default: status = .rotating
      }
      return ThingsDiaryEncryptionKey(id: key.id, value: openedKey, status: status)
    }
  }

  public func getDiaryChanges(
    diaryID: String,
    since: Date? = nil,
    limit: Int? = nil,
    nextPageToken: String? = nil
  ) async throws -> ThingsDiaryChangesPage {
    guard let authentication else { throw ThingsDiaryClientError.notAuthenticated }
    var requestURL = url(["v1", "diaries", diaryID, "changes"])
    var queryItems: [URLQueryItem] = []
    if let nextPageToken {
      queryItems.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
    }
    if let since {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      queryItems.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
    }
    if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
    if !queryItems.isEmpty {
      var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)!
      components.queryItems = queryItems
      requestURL = components.url!
    }
    let response = try await transport.send(
      ThingsDiaryHTTPRequest(
        url: requestURL,
        method: "GET",
        headers: ["Authorization": "Bearer \(authentication.token)"]
      ))
    guard response.statusCode == 200 else {
      throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
    }
    let decoder = JSONDecoder.thingsDiary()
    let page = try decoder.decode(DiaryChangesResponse.self, from: response.body)
    return ThingsDiaryChangesPage(changes: page.changes, nextPageToken: page.nextPageToken)
  }

  private func encodeDetails(title: String, description: String) throws -> Data {
    var details = Io_Thingsdiary_V1_DiaryDetails()
    details.title = title
    details.description_p = description
    return try details.serializedData()
  }

}

private struct DiaryChangesResponse: Decodable {
  let changes: [ThingsDiaryChange]
  let nextPageToken: String?

  enum CodingKeys: String, CodingKey {
    case changes
    case nextPageToken = "next_page_token"
  }
}

private func randomSymmetricKey() -> Data {
  let key = SymmetricKey(size: .bits256)
  return key.withUnsafeBytes { Data($0) }
}
