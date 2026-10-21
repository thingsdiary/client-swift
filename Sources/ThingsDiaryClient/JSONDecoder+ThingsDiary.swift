import Foundation

extension JSONDecoder {
  static func thingsDiary() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)

      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) {
        return date
      }

      let wholeSeconds = ISO8601DateFormatter()
      wholeSeconds.formatOptions = [.withInternetDateTime]
      if let date = wholeSeconds.date(from: value) {
        return date
      }

      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Expected an RFC 3339 timestamp."
        )
      )
    }
    return decoder
  }
}
