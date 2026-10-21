import Foundation
import SwiftProtobuf
import Testing

@testable import ThingsDiaryClient

@Test("Diaries use the protobuf RPC and decrypt its response")
func diariesUseProtobufRPC() async throws {
  let realtime = MockRealtimeTransport()
  let credentials = try realtimeTestCredentials()
  realtime.handler = { method, data in
    #expect(method == "io.thingsdiary.v1.diary.list")
    let request = try Io_Thingsdiary_V1_ListDiariesRequest(serializedBytes: data)
    #expect(request.page.pageToken == "cursor")
    return try listDiariesTestResponse(credentials: credentials).serializedData()
  }
  let client = try await authenticatedMockClient(realtime: realtime)

  let page = try await client.diaries(nextPageToken: "cursor")

  #expect(page.items.map(\.title) == ["Private title"])
  #expect(page.nextPageToken == "next")
}

@Test("Diary creation returns the decrypted RPC result")
func createDiaryReturnsRPCResult() async throws {
  let realtime = MockRealtimeTransport()
  let credentials = try realtimeTestCredentials()
  realtime.handler = { method, data in
    #expect(method == "io.thingsdiary.v1.diary.create")
    _ = try Io_Thingsdiary_V1_CreateDiaryRequest(serializedBytes: data)

    var response = Io_Thingsdiary_V1_CreateDiaryResponse()
    response.diary = try listDiariesTestResponse(credentials: credentials).diaries[0]
    return try response.serializedData()
  }
  let client = try await authenticatedMockClient(realtime: realtime)

  let diary = try await client.createDiary(title: "Requested", description: "Requested")

  #expect(diary.id == "diary-1")
  #expect(diary.title == "Private title")
}

@Test("Diary events are delivered to every subscriber")
func diaryEventsAreMulticast() async {
  let broadcaster = RealtimeEventBroadcaster()
  let first = broadcaster.stream()
  let second = broadcaster.stream()
  let firstValue = Task { await first.first(where: { _ in true }) }
  let secondValue = Task { await second.first(where: { _ in true }) }
  let event = Data([1, 2, 3])

  broadcaster.yield(event)

  #expect(await firstValue.value == event)
  #expect(await secondValue.value == event)
}

@Test("Diary create, get, list, and update return decrypted server data")
func serverDiaryOperations() async throws {
  let session = try await makeServerTestSession(resource: "diary")
  let created = try await session.client.createDiary(
    title: "Server diary",
    description: "Created by the Swift diary integration test"
  )

  #expect(!created.id.isEmpty)
  #expect(created.title == "Server diary")

  let fetched = try await session.client.getDiary(id: created.id)
  #expect(fetched.id == created.id)
  #expect(fetched.title == created.title)
  #expect(fetched.description == created.description)
  #expect(fetched.version == created.version)

  let listed = try await session.client.diaries()
  #expect(listed.items.count == 1)
  #expect(listed.items.first?.id == created.id)
  #expect(listed.items.first?.title == created.title)

  let updated = try await session.client.updateDiary(
    created,
    params: ThingsDiaryDiaryParams(
      title: "Updated server diary",
      description: "Updated by the Swift diary integration test"
    )
  )
  #expect(updated.id == created.id)
  #expect(updated.title == "Updated server diary")
  #expect(updated.version > created.version)

  await session.client.disconnect()
}

@Test("Diary deletion removes the diary from subsequent server responses")
func serverDiaryDeletion() async throws {
  let session = try await makeServerTestSession(resource: "diary-delete")
  let diary = try await makeServerTestDiary(client: session.client, resource: "diary deletion")

  try await session.client.deleteDiary(id: diary.id)

  let listed = try await session.client.diaries()
  #expect(listed.items.isEmpty)

  await session.client.disconnect()
}

@Test("Diary keys are returned by the server and decrypted")
func serverDiaryKeys() async throws {
  let session = try await makeServerTestSession(resource: "keys")
  let diary = try await makeServerTestDiary(client: session.client, resource: "keys")

  let keys = try await session.client.getDiaryKeys(diaryID: diary.id)

  #expect(keys.count == 1)
  #expect(keys.first?.status == .active)
  #expect(keys.first?.value.count == 32)

  await session.client.disconnect()
}

@Test(
  "Production diary creation and listing are compatible",
  .enabled(if: ProcessInfo.processInfo.environment["THINGSDIARY_LIVE_TESTS"] == "1")
)
func productionDiaryCreationAndListing() async throws {
  let session = try await makeProductionTestSession(resource: "diary-production")
  let title = "Swift production diary \(UUID().uuidString.lowercased())"

  let created = try await session.client.createDiary(
    title: title,
    description: "Created by the Swift production diary test"
  )
  let diaries = try await session.client.diaries()

  #expect(created.title == title)
  #expect(diaries.items.map(\.id).contains(created.id))

  await session.client.disconnect()
}
