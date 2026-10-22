import Foundation

extension ThingsDiaryClient {
  public func getDiary(id: String) async throws -> ThingsDiaryDiary {
    guard let authentication else {
      throw ThingsDiaryClientError.notAuthenticated
    }

    var request = Io_Thingsdiary_V1_GetDiaryRequest()
    request.diaryID = id
    let response = try await rpc(
      "io.thingsdiary.v1.diary.get",
      request: request,
      response: Io_Thingsdiary_V1_GetDiaryResponse.self
    )
    return try decrypt(response.diary.wire, credentials: authentication.credentials)
  }
}
