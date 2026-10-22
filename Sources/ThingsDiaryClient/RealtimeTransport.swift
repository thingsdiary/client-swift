import Foundation
import SwiftCentrifuge
import SwiftProtobuf

public protocol ThingsDiaryRealtimeTransport: Sendable {
  func connect(
    token: String,
    tokenProvider: @escaping @Sendable () async throws -> String
  ) async throws
  func disconnect() async
  func rpc(method: String, data: Data) async throws -> Data
  func events() -> AsyncStream<Data>
}

public final class CentrifugeRealtimeTransport: NSObject, ThingsDiaryRealtimeTransport,
  CentrifugeClientDelegate, @unchecked Sendable
{
  private let endpoint: URL
  private let lock = NSLock()
  private var client: CentrifugeClient?
  private var connectContinuation: CheckedContinuation<Void, Error>?
  private let eventBroadcaster = RealtimeEventBroadcaster()

  public init(endpoint: URL) {
    self.endpoint = endpoint
  }

  public func connect(
    token: String,
    tokenProvider: @escaping @Sendable () async throws -> String
  ) async throws {
    let client = CentrifugeClient(
      endpoint: endpoint.absoluteString,
      config: CentrifugeClientConfig(
        token: token,
        useNativeWebSocket: true,
        tokenGetter: { _, completion in
          let completion = TokenCompletion(completion)
          Task {
            do {
              completion.call(.success(try await tokenProvider()))
            } catch {
              completion.call(.failure(error))
            }
          }
        }
      ),
      delegate: self
    )

    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        self.client?.disconnect()
        self.client = client
        self.connectContinuation = continuation
      }
      client.connect()
    }
  }

  public func disconnect() async {
    lock.withLock {
      client?.disconnect()
      client = nil
      connectContinuation = nil
    }
  }

  public func rpc(method: String, data: Data) async throws -> Data {
    let connectedClient = try lock.withLock {
      guard let client = self.client else {
        throw ThingsDiaryClientError.realtimeNotConnected
      }
      return client
    }
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Data, Error>) in
      connectedClient.rpc(method: method, data: data) { result in
        continuation.resume(with: result.map { $0.data })
      }
    }
  }

  public func events() -> AsyncStream<Data> {
    eventBroadcaster.stream()
  }

  public func onConnected(_ client: CentrifugeClient, _ event: CentrifugeConnectedEvent) {
    let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
      guard client === self.client else { return nil }
      defer { connectContinuation = nil }
      return connectContinuation
    }
    continuation?.resume()
  }

  public func onDisconnected(_ client: CentrifugeClient, _ event: CentrifugeDisconnectedEvent) {
    let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
      guard client === self.client else { return nil }
      defer { connectContinuation = nil }
      return connectContinuation
    }
    continuation?.resume(
      throwing: ThingsDiaryClientError.realtimeDisconnected(
        code: event.code,
        reason: event.reason
      ))
  }

  public func onPublication(_ client: CentrifugeClient, _ event: CentrifugeServerPublicationEvent) {
    eventBroadcaster.yield(event.data)
  }
}

final class RealtimeEventBroadcaster: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Data>.Continuation] = [:]

  func stream() -> AsyncStream<Data> {
    let id = UUID()
    return AsyncStream { continuation in
      lock.withLock {
        continuations[id] = continuation
      }
      continuation.onTermination = { [weak self] _ in
        self?.remove(id)
      }
    }
  }

  func yield(_ data: Data) {
    let subscribers = lock.withLock { Array(continuations.values) }
    for subscriber in subscribers {
      subscriber.yield(data)
    }
  }

  private func remove(_ id: UUID) {
    lock.withLock {
      continuations[id] = nil
    }
  }
}

private final class TokenCompletion: @unchecked Sendable {
  private let body: (Result<String, Error>) -> Void

  init(_ body: @escaping (Result<String, Error>) -> Void) {
    self.body = body
  }

  func call(_ result: Result<String, Error>) {
    body(result)
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

extension ThingsDiaryClient {
  private static let envelopeVersion: UInt32 = 1

  public func connect() async throws {
    guard authentication != nil else {
      throw ThingsDiaryClientError.notAuthenticated
    }
    try await realtimeTransport.connect(
      token: try await getRealtimeToken(),
      tokenProvider: { [weak self] in
        guard let self else { throw ThingsDiaryClientError.notAuthenticated }
        return try await self.getRealtimeToken()
      }
    )
  }

  public func disconnect() async {
    await realtimeTransport.disconnect()
  }

  public func events() -> AsyncThrowingStream<Io_Thingsdiary_V1_Event, Error> {
    let source = realtimeTransport.events()
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for await data in source {
            continuation.yield(try Io_Thingsdiary_V1_Event(serializedBytes: data))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func rpc<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    _ method: String,
    request: Request,
    response: Response.Type
  ) async throws -> Response {
    guard let authentication else {
      throw ThingsDiaryClientError.notAuthenticated
    }
    do {
      let data = try await realtimeTransport.rpc(
        method: method,
        data: try signedEnvelopeData(
          method: method,
          payload: request.serializedData(),
          signingPrivateKey: authentication.credentials.signingPrivateKey
        )
      )
      return try Response(serializedBytes: data)
    } catch let error as CentrifugeError {
      throw mapRealtimeError(error)
    }
  }

  func rpc<Request: SwiftProtobuf.Message>(
    _ method: String,
    request: Request
  ) async throws {
    guard let authentication else {
      throw ThingsDiaryClientError.notAuthenticated
    }
    do {
      _ = try await realtimeTransport.rpc(
        method: method,
        data: try signedEnvelopeData(
          method: method,
          payload: request.serializedData(),
          signingPrivateKey: authentication.credentials.signingPrivateKey
        )
      )
    } catch let error as CentrifugeError {
      throw mapRealtimeError(error)
    }
  }

  private func signedEnvelopeData(
    method: String,
    payload: Data,
    signingPrivateKey: Data
  ) throws -> Data {
    var envelope = Io_Thingsdiary_V1_Envelope()
    envelope.version = Self.envelopeVersion
    envelope.method = method
    envelope.payload = payload
    envelope.operationID = UUID().uuidString.lowercased()

    let envelopeData = try envelope.serializedData()
    var signedEnvelope = Io_Thingsdiary_V1_SignedEnvelope()
    signedEnvelope.envelope = envelopeData
    signedEnvelope.signature = try ThingsDiaryCrypto.sign(
      envelopeData,
      privateKey: signingPrivateKey
    )

    return try signedEnvelope.serializedData()
  }

  private func getRealtimeToken() async throws -> String {
    guard let authentication else {
      throw ThingsDiaryClientError.notAuthenticated
    }
    let response = try await transport.send(
      ThingsDiaryHTTPRequest(
        url: url(["v1", "realtime", "token"]),
        method: "POST",
        headers: ["Authorization": "Bearer \(authentication.token)"]
      ))
    guard response.statusCode == 200 else {
      throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
    }
    return try JSONDecoder().decode(RealtimeTokenResponse.self, from: response.body).token
  }

  private func mapRealtimeError(_ error: CentrifugeError) -> ThingsDiaryClientError {
    guard case .replyError(let code, let message, _) = error else {
      return .realtime(String(describing: error))
    }
    return .rpc(code: code, message: message)
  }
}

private struct RealtimeTokenResponse: Decodable {
  let token: String
}
