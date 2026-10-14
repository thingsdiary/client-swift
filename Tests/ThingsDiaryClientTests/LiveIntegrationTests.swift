import Foundation
import Testing
@testable import ThingsDiaryClient

@Test(
    "Production registration, login, and diary listing are compatible",
    .enabled(if: ProcessInfo.processInfo.environment["THINGSDIARY_LIVE_TESTS"] == "1")
)
func productionRegistrationLoginAndDiaries() async throws {
    let identifier = UUID().uuidString.lowercased()
    let login = "codex.swift.\(identifier)@thingsdiary.io"
    let password = "Codex integration \(identifier)"
    let secretKey = ThingsDiarySecretKey.generate().rawValue
    let kdfSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    let registrationClient = ThingsDiaryClient()
    let registered: ThingsDiaryAuthState
    do {
        registered = try await registrationClient.register(
            login: login,
            password: password,
            secretKey: secretKey,
            kdfSalt: kdfSalt
        )
    } catch let ThingsDiaryClientError.httpStatus(status, body) {
        Issue.record("Registration returned HTTP \(status): \(String(decoding: body, as: UTF8.self))")
        return
    }
    #expect(!registered.token.isEmpty)

    let title = "Swift live test \(identifier)"
    let createdDiary = try await registrationClient.createDiary(
        title: title,
        description: "Created by the opt-in Swift integration test"
    )
    #expect(createdDiary.title == title)

    let loginClient = ThingsDiaryClient()
    let authenticated = try await loginClient.login(
        login: login,
        password: password,
        secretKey: secretKey
    )
    #expect(!authenticated.token.isEmpty)

    let diaries = try await loginClient.diaries()
    #expect(diaries.items.map(\.title) == [title])
}
