import Foundation

extension ThingsDiaryClient {
    public func getDiary(id: String) async throws -> ThingsDiaryDiary {
        guard let authentication else {
            throw ThingsDiaryClientError.notAuthenticated
        }

        let request = ThingsDiaryHTTPRequest(
            url: url(["v1", "diaries", id]),
            method: "GET",
            headers: ["Authorization": "Bearer \(authentication.token)"]
        )
        let response = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw ThingsDiaryClientError.httpStatus(
                response.statusCode,
                body: response.body
            )
        }

        let decoder = JSONDecoder.thingsDiary()
        let wireDiary = try decoder.decode(DiaryResponse.self, from: response.body).diary
        return try decrypt(wireDiary, credentials: authentication.credentials)
    }
}

private struct DiaryResponse: Decodable {
    let diary: WireDiary
}
