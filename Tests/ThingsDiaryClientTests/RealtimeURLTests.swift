import Foundation
import Testing

@testable import ThingsDiaryClient

@Test("Realtime URL follows local and remote routing")
func realtimeURLFollowsLocalAndRemoteRouting() throws {
  let tests = [
    (
      "https://cloud.thingsdiary.io/api",
      "wss://cloud.thingsdiary.io/api/v1/realtime"
    ),
    (
      "http://example.test:8081/api/",
      "ws://example.test:8081/api/v1/realtime"
    ),
    (
      "http://localhost:8081/api",
      "ws://localhost:8000/connection/websocket"
    ),
    (
      "https://localhost/api",
      "ws://localhost:8000/connection/websocket"
    ),
    (
      "http://127.0.0.1:8081/api",
      "ws://127.0.0.1:8000/connection/websocket"
    ),
    (
      "http://[::1]:8081/api",
      "ws://[::1]:8000/connection/websocket"
    ),
    (
      "https://example.test/api?debug=true#fragment",
      "wss://example.test/api/v1/realtime"
    ),
  ]

  for (baseURL, expected) in tests {
    let baseURL = try #require(URL(string: baseURL))
    #expect(ThingsDiaryClient.realtimeURL(from: baseURL).absoluteString == expected)
  }
}
