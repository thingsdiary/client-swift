import Testing
@testable import ThingsDiaryClient

@Test("Entry create, get, list, and update return decrypted server data")
func serverEntryOperations() async throws {
    let session = try await makeServerTestSession(resource: "entry")
    let diary = try await makeServerTestDiary(client: session.client, resource: "entry")
    let topic = try await session.client.createTopic(
        diaryID: diary.id,
        params: ThingsDiaryTopicParams(
            title: "Entry topic",
            description: "Topic for the entry integration test",
            color: "#abcdef"
        )
    )
    let created = try await session.client.createEntry(
        diaryID: diary.id,
        params: ThingsDiaryEntryParams(
            content: "Server entry content",
            topicID: topic.id,
            bookmarked: true
        )
    )

    #expect(!created.id.isEmpty)
    #expect(created.diaryID == diary.id)
    #expect(created.topicID == topic.id)
    #expect(created.content == "Server entry content")
    #expect(created.bookmarked)

    let fetched = try await session.client.getEntry(diaryID: diary.id, entryID: created.id)
    #expect(fetched.id == created.id)
    #expect(fetched.content == created.content)
    #expect(fetched.topicID == created.topicID)
    #expect(fetched.version == created.version)

    let listed = try await session.client.entries(diaryID: diary.id)
    #expect(listed.items.count == 1)
    #expect(listed.items.first?.id == created.id)
    #expect(listed.items.first?.content == created.content)

    let updated = try await session.client.updateEntry(
        created,
        params: ThingsDiaryEntryParams(
            content: "Updated server entry content",
            archived: true,
            previewHidden: true
        )
    )
    #expect(updated.id == created.id)
    #expect(updated.content == "Updated server entry content")
    #expect(updated.archived)
    #expect(updated.previewHidden)
    #expect(updated.version > created.version)

    await session.client.disconnect()
}

@Test("Entry soft deletion and restoration return the expected server state")
func serverEntryDeletionAndRestoration() async throws {
    let session = try await makeServerTestSession(resource: "entry-restore")
    let diary = try await makeServerTestDiary(client: session.client, resource: "entry restoration")
    let entry = try await session.client.createEntry(
        diaryID: diary.id,
        params: ThingsDiaryEntryParams(content: "Restorable entry")
    )

    try await session.client.deleteEntry(diaryID: diary.id, entryID: entry.id, soft: true)

    let deleted = try await session.client.getEntry(diaryID: diary.id, entryID: entry.id)
    #expect(deleted.deletedAt != nil)

    let restored = try await session.client.restoreEntry(diaryID: diary.id, entryID: entry.id)
    #expect(restored.id == entry.id)
    #expect(restored.deletedAt == nil)

    await session.client.disconnect()
}
