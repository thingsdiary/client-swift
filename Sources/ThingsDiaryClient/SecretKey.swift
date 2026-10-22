import Foundation

public struct ThingsDiarySecretKey: Sendable, Equatable, Hashable {
  public let rawValue: String

  private init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static func generate() -> Self {
    var generator = SystemRandomNumberGenerator()
    let entropy = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    let payload =
      CrockfordBase32.encode(entropy)
      + String(CrockfordBase32.checkSymbol(for: entropy))
    return Self(rawValue: "TDKV1-" + payload.grouped(every: 4))
  }

  public static func parse(_ input: String) throws -> Self {
    let canonical = CrockfordBase32.canonicalize(input)
    guard canonical.hasPrefix("TDKV1") else {
      throw ThingsDiarySecretKeyError.invalidPrefix
    }

    let payload = String(canonical.dropFirst(5))
    guard payload.count == 27 else {
      throw ThingsDiarySecretKeyError.invalidLength
    }

    let encoded = String(payload.dropLast())
    let suppliedCheckSymbol = try payload.last.required()
    let entropy = try CrockfordBase32.decode(encoded)
    guard entropy.count == 16 else {
      throw ThingsDiarySecretKeyError.invalidLength
    }
    guard CrockfordBase32.checkSymbol(for: entropy) == suppliedCheckSymbol else {
      throw ThingsDiarySecretKeyError.invalidChecksum
    }

    return Self(rawValue: "TDKV1-" + payload.grouped(every: 4))
  }
}

public enum ThingsDiarySecretKeyError: Error, Sendable, Equatable {
  case invalidPrefix
  case invalidLength
  case invalidCharacter
  case invalidChecksum
}

private enum CrockfordBase32 {
  static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
  static let checkAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ*~$=U")

  static func canonicalize(_ input: String) -> String {
    input
      .filter { $0 != "-" && !$0.isWhitespace }
      .uppercased()
      .map { character in
        switch character {
        case "O": "0"
        case "I", "L": "1"
        default: character
        }
      }
      .reduce(into: "") { $0.append($1) }
  }

  static func encode(_ bytes: [UInt8]) -> String {
    var output = ""
    var bits = 0
    var value = 0

    for byte in bytes {
      value = (value << 8) | Int(byte)
      bits += 8

      while bits >= 5 {
        output.append(alphabet[(value >> (bits - 5)) & 31])
        bits -= 5
      }
      value &= (1 << bits) - 1
    }

    if bits > 0 {
      output.append(alphabet[(value << (5 - bits)) & 31])
    }
    return output
  }

  static func decode(_ encoded: String) throws -> [UInt8] {
    var output: [UInt8] = []
    var bits = 0
    var value = 0

    for character in encoded {
      guard let index = alphabet.firstIndex(of: character) else {
        throw ThingsDiarySecretKeyError.invalidCharacter
      }
      value = (value << 5) | index
      bits += 5

      if bits >= 8 {
        output.append(UInt8((value >> (bits - 8)) & 0xff))
        bits -= 8
        value &= (1 << bits) - 1
      }
    }
    return output
  }

  static func checkSymbol(for bytes: [UInt8]) -> Character {
    let remainder = bytes.reduce(0) { (($0 * 256) + Int($1)) % 37 }
    return checkAlphabet[remainder]
  }
}

extension String {
  fileprivate func grouped(every size: Int) -> String {
    stride(from: 0, to: count, by: size)
      .map { offset in
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
        return String(self[start..<end])
      }
      .joined(separator: "-")
  }
}

extension Optional {
  fileprivate func required() throws -> Wrapped {
    guard let value = self else {
      throw ThingsDiarySecretKeyError.invalidLength
    }
    return value
  }
}
