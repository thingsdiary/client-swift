import Foundation

extension ThingsDiaryClient {
  public func currentSession() async throws -> Bool {
    guard let authentication else {
      throw ThingsDiaryClientError.notAuthenticated
    }
    let request = ThingsDiaryHTTPRequest(
      url: url(["v1", "auth", "sessions", "current"]),
      method: "GET",
      headers: ["Authorization": "Bearer \(authentication.token)"]
    )
    let response = try await transport.send(request)
    switch response.statusCode {
    case 204:
      return true
    case 401:
      return false
    default:
      throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
    }
  }
}
