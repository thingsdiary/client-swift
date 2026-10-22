import Foundation

public struct ThingsDiaryHTTPRequest: Sendable, Equatable {
  public let url: URL
  public let method: String
  public let headers: [String: String]
  public let body: Data

  public init(
    url: URL,
    method: String,
    headers: [String: String] = [:],
    body: Data = Data()
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

public struct ThingsDiaryHTTPResponse: Sendable, Equatable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

public protocol ThingsDiaryTransport: Sendable {
  func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse
}

public struct URLSessionTransport: ThingsDiaryTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body.isEmpty ? nil : request.body
    for (name, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }

    let (body, response) = try await session.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ThingsDiaryClientError.invalidResponse
    }
    return ThingsDiaryHTTPResponse(
      statusCode: httpResponse.statusCode,
      body: body
    )
  }
}
