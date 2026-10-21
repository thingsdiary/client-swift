import Foundation
import SwiftProtobuf
import Testing

@testable import ThingsDiaryClient

@Test("Topic delete options retain protobuf presence")
func deleteTopicUsesProtoOptionals() async throws {
  let realtime = MockRealtimeTransport()
  realtime.handler = { method, data in
    #expect(method == "io.thingsdiary.v1.topic.delete")
    let request = try Io_Thingsdiary_V1_DeleteTopicRequest(serializedBytes: data)
    #expect(request.diaryID == "diary-1")
    #expect(request.topicID == "topic-1")
    #expect(request.hasSoft)
    #expect(request.soft)
    #expect(request.deleteEntries)
    return Data()
  }
  let client = try await authenticatedMockClient(realtime: realtime)

  try await client.deleteTopic(
    diaryID: "diary-1",
    topicID: "topic-1",
    deleteEntries: true,
    soft: true
  )
}

@Test("Topic create, get, list, and update return decrypted server data")
func serverTopicOperations() async throws {
  let session = try await makeServerTestSession(resource: "topic")
  let diary = try await makeServerTestDiary(client: session.client, resource: "topic")
  let created = try await session.client.createTopic(
    diaryID: diary.id,
    params: ThingsDiaryTopicParams(
      title: "Server topic",
      description: "Created by the Swift topic integration test",
      color: "#123456",
      entryPreviewable: false
    )
  )

  #expect(!created.id.isEmpty)
  #expect(created.diaryID == diary.id)
  #expect(created.title == "Server topic")
  #expect(created.color == "#123456")
  #expect(!created.entryPreviewable)

  let fetched = try await session.client.getTopic(diaryID: diary.id, topicID: created.id)
  #expect(fetched.id == created.id)
  #expect(fetched.title == created.title)
  #expect(fetched.description == created.description)
  #expect(fetched.color == created.color)
  #expect(fetched.version == created.version)

  let listed = try await session.client.topics(diaryID: diary.id)
  #expect(listed.items.count == 1)
  #expect(listed.items.first?.id == created.id)
  #expect(listed.items.first?.title == created.title)

  let updated = try await session.client.updateTopic(
    created,
    params: ThingsDiaryTopicParams(
      title: "Updated server topic",
      description: "Updated by the Swift topic integration test",
      color: "#654321"
    )
  )
  #expect(updated.id == created.id)
  #expect(updated.title == "Updated server topic")
  #expect(updated.version > created.version)

  await session.client.disconnect()
}

@Test("Topic soft deletion and restoration return the expected server state")
func serverTopicDeletionAndRestoration() async throws {
  let session = try await makeServerTestSession(resource: "topic-restore")
  let diary = try await makeServerTestDiary(client: session.client, resource: "topic restoration")
  let topic = try await session.client.createTopic(
    diaryID: diary.id,
    params: ThingsDiaryTopicParams(
      title: "Restorable topic",
      description: "Topic for delete and restore",
      color: "#112233"
    )
  )

  try await session.client.deleteTopic(diaryID: diary.id, topicID: topic.id, soft: true)

  let deleted = try await session.client.getTopic(diaryID: diary.id, topicID: topic.id)
  #expect(deleted.deletedAt != nil)

  let restored = try await session.client.restoreTopic(diaryID: diary.id, topicID: topic.id)
  #expect(restored.id == topic.id)
  #expect(restored.deletedAt == nil)

  await session.client.disconnect()
}
