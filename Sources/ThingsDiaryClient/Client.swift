import Foundation

public struct ThingsDiaryAuthState: Sendable, Equatable {
  public let token: String
  public let credentials: ThingsDiaryCredentials

  public init(token: String, credentials: ThingsDiaryCredentials) {
    self.token = token
    self.credentials = credentials
  }
}

public actor ThingsDiaryClient {
  public static let productionURL = URL(string: "https://cloud.thingsdiary.io/api")!

  let baseURL: URL
  let transport: any ThingsDiaryTransport
  let realtimeTransport: any ThingsDiaryRealtimeTransport
  var authentication: ThingsDiaryAuthState?

  public init(
    baseURL: URL = productionURL,
    realtimeURL: URL? = nil,
    transport: any ThingsDiaryTransport = URLSessionTransport(),
    realtimeTransport: (any ThingsDiaryRealtimeTransport)? = nil
  ) {
    self.baseURL = baseURL
    self.transport = transport
    self.realtimeTransport =
      realtimeTransport
      ?? CentrifugeRealtimeTransport(
        endpoint: realtimeURL ?? Self.realtimeURL(from: baseURL)
      )
  }

  @discardableResult
  public func login(
    login: String,
    password: String,
    secretKey: String
  ) async throws -> ThingsDiaryAuthState {
    let challenge: LoginResponse = try await post(
      path: ["v1", "auth", "login"],
      body: LoginRequest(login: login, password: password)
    )
    guard let nonce = Data(base64Encoded: challenge.nonce) else {
      throw ThingsDiaryClientError.invalidBase64
    }

    let credentials = try ThingsDiaryCrypto.deriveCredentials(
      secretKey: secretKey,
      salt: challenge.kdfSalt
    )
    let signature = try ThingsDiaryCrypto.sign(
      nonce,
      privateKey: credentials.signingPrivateKey
    )
    let verified: LoginVerifyResponse = try await post(
      path: ["v1", "auth", "login", "verify"],
      body: LoginVerifyRequest(
        challengeID: challenge.challengeID,
        signedNonce: signature.base64EncodedString()
      )
    )
    let state = ThingsDiaryAuthState(
      token: verified.token,
      credentials: credentials
    )
    authentication = state
    return state
  }

  public func diaries(
    nextPageToken: String? = nil
  ) async throws -> ThingsDiaryPage<ThingsDiaryDiary> {
    guard let authentication else {
      throw ThingsDiaryClientError.notAuthenticated
    }

    var request = Io_Thingsdiary_V1_ListDiariesRequest()
    request.page.pageToken = nextPageToken ?? ""
    let response = try await rpc(
      "io.thingsdiary.v1.diary.list",
      request: request,
      response: Io_Thingsdiary_V1_ListDiariesResponse.self
    )
    let diaries = try response.diaries.map {
      try decrypt($0.wire, credentials: authentication.credentials)
    }
    return ThingsDiaryPage(
      items: diaries,
      nextPageToken: response.page.nextPageToken.nilIfEmpty
    )
  }

  public func allDiaries() async throws -> [ThingsDiaryDiary] {
    var result: [ThingsDiaryDiary] = []
    var nextPageToken: String?

    repeat {
      let page = try await diaries(nextPageToken: nextPageToken)
      result.append(contentsOf: page.items)
      nextPageToken = page.nextPageToken
    } while nextPageToken != nil

    return result
  }

  private func post<Request: Encodable, Response: Decodable & Sendable>(
    path: [String],
    body: Request
  ) async throws -> Response {
    let encoded = try JSONEncoder().encode(body)
    let request = ThingsDiaryHTTPRequest(
      url: url(path),
      method: "POST",
      headers: ["Content-Type": "application/json"],
      body: encoded
    )
    let response = try await transport.send(request)
    guard (200..<300).contains(response.statusCode) else {
      throw ThingsDiaryClientError.httpStatus(
        response.statusCode,
        body: response.body
      )
    }
    return try JSONDecoder().decode(Response.self, from: response.body)
  }

  func url(_ path: [String]) -> URL {
    path.reduce(baseURL) { url, component in
      url.appendingPathComponent(component)
    }
  }

  static func realtimeURL(from baseURL: URL) -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.scheme = baseURL.scheme == "http" ? "ws" : "wss"
    if isLocalhost(baseURL.host) {
      components.scheme = "ws"
      components.port = 8000
      components.path = "/connection/websocket"
    } else {
      let basePath = baseURL.path.trimmingCharacters(
        in: CharacterSet(charactersIn: "/")
      )
      components.path =
        basePath.isEmpty
        ? "/v1/realtime"
        : "/\(basePath)/v1/realtime"
    }
    components.query = nil
    components.fragment = nil
    return components.url!
  }

  private static func isLocalhost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }

  func decrypt(
    _ diary: WireDiary,
    credentials: ThingsDiaryCredentials
  ) throws -> ThingsDiaryDiary {
    guard
      let encryptedDiaryKey = diary.encryptionKeys.first(where: {
        $0.status == "active"
      }) ?? diary.encryptionKeys.first
    else {
      throw ThingsDiaryClientError.missingActiveEncryptionKey
    }
    let diaryKey = try ThingsDiaryCrypto.openSealedBox(
      try decodeBase64(encryptedDiaryKey.value),
      recipientPrivateKey: credentials.encryptionPrivateKey,
      recipientPublicKey: credentials.encryptionPublicKey
    )
    let entityKey = try ThingsDiaryCrypto.decrypt(
      try decodeBase64(diary.encryption.encryptedKeyData),
      key: diaryKey,
      nonce: try decodeBase64(diary.encryption.encryptedKeyNonce)
    )
    let detailsData = try ThingsDiaryCrypto.decrypt(
      try decodeBase64(diary.details.data),
      key: entityKey,
      nonce: try decodeBase64(diary.details.nonce)
    )
    let details = try JSONDecoder().decode(DiaryDetails.self, from: detailsData)

    return ThingsDiaryDiary(
      id: diary.id,
      title: details.title,
      description: details.description,
      createdAt: diary.createdAt,
      updatedAt: diary.updatedAt,
      version: diary.version
    )
  }

  func decodeBase64(_ value: String) throws -> Data {
    guard let data = Data(base64Encoded: value) else {
      throw ThingsDiaryClientError.invalidBase64
    }
    return data
  }
}

public enum ThingsDiaryClientError: Error, Sendable, Equatable {
  case invalidResponse
  case invalidBase64
  case httpStatus(Int, body: Data)
  case notAuthenticated
  case missingActiveEncryptionKey
  case realtimeNotConnected
  case realtimeDisconnected(code: UInt32, reason: String)
  case realtime(String)
  case rpc(code: UInt32, message: String)
}

private struct LoginRequest: Encodable {
  let login: String
  let password: String
}

private struct LoginResponse: Decodable, Sendable {
  let challengeID: String
  let nonce: String
  let kdfSalt: String

  enum CodingKeys: String, CodingKey {
    case challengeID = "challenge_id"
    case nonce
    case kdfSalt = "kdf_salt"
  }
}

private struct LoginVerifyRequest: Encodable {
  let challengeID: String
  let signedNonce: String

  enum CodingKeys: String, CodingKey {
    case challengeID = "challenge_id"
    case signedNonce = "signed_nonce"
  }
}

private struct LoginVerifyResponse: Decodable, Sendable {
  let token: String
}

struct WireDiary: Decodable, Sendable {
  let id: String
  let version: UInt64
  let createdAt: Date
  let updatedAt: Date
  let encryptionKeys: [WireEncryptionKey]
  let encryption: WireDiaryEncryption
  let details: WireEncryptedData

  enum CodingKeys: String, CodingKey {
    case id, version, encryption, details
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case encryptionKeys = "encryption_keys"
  }
}

struct WireEncryptionKey: Decodable, Sendable {
  let value: String
  let status: String
}

struct WireDiaryEncryption: Decodable, Sendable {
  let encryptedKeyNonce: String
  let encryptedKeyData: String

  enum CodingKeys: String, CodingKey {
    case encryptedKeyNonce = "encrypted_key_nonce"
    case encryptedKeyData = "encrypted_key_data"
  }
}

struct WireEncryptedData: Decodable, Sendable {
  let nonce: String
  let data: String
}

struct DiaryDetails: Decodable, Sendable {
  let title: String
  let description: String
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
