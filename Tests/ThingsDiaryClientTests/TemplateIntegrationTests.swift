import Testing
@testable import ThingsDiaryClient

@Test("Template create, get, list, and update return decrypted server data")
func serverTemplateOperations() async throws {
    let session = try await makeServerTestSession(resource: "template")
    let diary = try await makeServerTestDiary(client: session.client, resource: "template")
    let created = try await session.client.createTemplate(
        diaryID: diary.id,
        params: ThingsDiaryTemplateParams(content: "# Server template")
    )

    #expect(!created.id.isEmpty)
    #expect(created.diaryID == diary.id)
    #expect(created.content == "# Server template")

    let fetched = try await session.client.getTemplate(diaryID: diary.id, templateID: created.id)
    #expect(fetched.id == created.id)
    #expect(fetched.content == created.content)
    #expect(fetched.version == created.version)

    let listed = try await session.client.templates(diaryID: diary.id)
    #expect(listed.items.count == 1)
    #expect(listed.items.first?.id == created.id)
    #expect(listed.items.first?.content == created.content)

    let updated = try await session.client.updateTemplate(
        created,
        params: ThingsDiaryTemplateParams(content: "# Updated server template")
    )
    #expect(updated.id == created.id)
    #expect(updated.content == "# Updated server template")
    #expect(updated.version > created.version)

    await session.client.disconnect()
}

@Test("Template soft deletion and restoration return the expected server state")
func serverTemplateDeletionAndRestoration() async throws {
    let session = try await makeServerTestSession(resource: "template-restore")
    let diary = try await makeServerTestDiary(client: session.client, resource: "template restoration")
    let template = try await session.client.createTemplate(
        diaryID: diary.id,
        params: ThingsDiaryTemplateParams(content: "Restorable template")
    )

    try await session.client.deleteTemplate(diaryID: diary.id, templateID: template.id, soft: true)

    let deleted = try await session.client.getTemplate(diaryID: diary.id, templateID: template.id)
    #expect(deleted.deletedAt != nil)

    let restored = try await session.client.restoreTemplate(diaryID: diary.id, templateID: template.id)
    #expect(restored.id == template.id)
    #expect(restored.deletedAt == nil)

    await session.client.disconnect()
}
