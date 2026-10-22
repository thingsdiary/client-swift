import Foundation
import Testing

@testable import ThingsDiaryClient

@Test("Connect exchanges the auth session for a realtime token")
func connectUsesRealtimeToken() async throws {
  let realtime = MockRealtimeTransport()
  let client = try await authenticatedMockClient(realtime: realtime)

  try await client.connect()

  #expect(realtime.connectedToken == "realtime-token")
}

@Test("Auth registration and login return usable server sessions")
func serverAuthRegistrationAndLogin() async throws {
  let registered = try await makeServerTestSession(resource: "auth")
  #expect(try await registered.client.currentSession())

  let loginClient = try makeServerTestClient()
  let authenticated = try await loginClient.login(
    login: registered.login,
    password: registered.password,
    secretKey: registered.secretKey
  )

  #expect(!authenticated.token.isEmpty)
  try await loginClient.connect()
  #expect(try await loginClient.diaries().items.isEmpty)

  await registered.client.disconnect()
  await loginClient.disconnect()
}

@Test(
  "Production auth registration and login are compatible",
  .enabled(if: ProcessInfo.processInfo.environment["THINGSDIARY_LIVE_TESTS"] == "1")
)
func productionAuthRegistrationAndLogin() async throws {
  let registered = try await makeProductionTestSession(resource: "auth-production")
  let loginClient = ThingsDiaryClient()

  let authenticated = try await loginClient.login(
    login: registered.login,
    password: registered.password,
    secretKey: registered.secretKey
  )

  #expect(!authenticated.token.isEmpty)
  try await loginClient.connect()
  #expect(try await loginClient.currentSession())

  await registered.client.disconnect()
  await loginClient.disconnect()
}
