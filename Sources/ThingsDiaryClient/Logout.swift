import Foundation

extension ThingsDiaryClient {
    public func logout() async throws {
        guard let state = authentication else {
            throw ThingsDiaryClientError.notAuthenticated
        }
        let request = ThingsDiaryHTTPRequest(
            url: url(["v1", "auth", "logout"]),
            method: "POST",
            headers: ["Authorization": "Bearer \(state.token)"]
        )
        let response = try await transport.send(request)
        guard response.statusCode == 204 else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }
        await realtimeTransport.disconnect()
        self.authentication = nil
    }
}
