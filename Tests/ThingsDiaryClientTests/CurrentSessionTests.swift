import Foundation
import Testing

@testable import ThingsDiaryClient

@Test("Current session maps 204 and 401 and rejects other statuses")
func currentSessionMapsExpectedStatuses() async throws {
  let activeClient = try await authenticatedClient(statusCode: 204)
  #expect(try await activeClient.currentSession())

  let inactiveClient = try await authenticatedClient(statusCode: 401)
  #expect(try await !inactiveClient.currentSession())

  let failingClient = try await authenticatedClient(statusCode: 503)
  do {
    _ = try await failingClient.currentSession()
    Issue.record("Expected an HTTP status error")
  } catch let error as ThingsDiaryClientError {
    #expect(error == .httpStatus(503, body: Data("unavailable".utf8)))
  }
}

private func authenticatedClient(statusCode: Int) async throws -> ThingsDiaryClient {
  let client = ThingsDiaryClient(
    baseURL: URL(string: "https://example.test/api")!,
    transport: CurrentSessionTransport(statusCode: statusCode)
  )
  _ = try await client.register(
    login: "person@example.test",
    password: "secret",
    secretKey: "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6",
    kdfSalt: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"
  )
  return client
}

private struct CurrentSessionTransport: ThingsDiaryTransport {
  let statusCode: Int

  func send(_ request: ThingsDiaryHTTPRequest) async throws -> ThingsDiaryHTTPResponse {
    switch request.url.path {
    case "/api/v1/auth/register":
      return ThingsDiaryHTTPResponse(
        statusCode: 201,
        body: Data(#"{"token":"session-token"}"#.utf8)
      )
    case "/api/v1/auth/sessions/current":
      #expect(request.method == "GET")
      #expect(request.headers["Authorization"] == "Bearer session-token")
      #expect(request.body.isEmpty)
      return ThingsDiaryHTTPResponse(
        statusCode: statusCode,
        body: statusCode == 503 ? Data("unavailable".utf8) : Data()
      )
    default:
      Issue.record("Unexpected request: \(request.url)")
      return ThingsDiaryHTTPResponse(statusCode: 404, body: Data())
    }
  }
}
