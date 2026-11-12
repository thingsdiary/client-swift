import Foundation
import SwiftProtobuf
import Testing

@testable import ThingsDiaryClient

// The Go and TypeScript SDK tests use the same wire vectors.
@Test("Domain payloads match the shared protobuf wire vectors")
func domainPayloadWireFormat() throws {
  var diary = Io_Thingsdiary_V1_DiaryDetails()
  diary.title = "Diary"
  diary.description_p = "Личное"
  try checkDomainWire(diary, "0a054469617279120cd09bd0b8d187d0bdd0bed0b5")

  var entry = Io_Thingsdiary_V1_EntryDetails()
  entry.content = "Hello 🌍"
  entry.archived = true
  entry.previewHidden = true
  try checkDomainWire(entry, "0a0a48656c6c6f20f09f8c8d10012001")

  var topic = Io_Thingsdiary_V1_TopicDetails()
  topic.title = "Topic"
  topic.color = "#123456"
  try checkDomainWire(topic, "0a05546f7069631a0723313233343536")

  var template = Io_Thingsdiary_V1_TemplateDetails()
  template.content = "Line 1\nLine 2"
  try checkDomainWire(template, "0a0d4c696e6520310a4c696e652032")
}

private func checkDomainWire<T: SwiftProtobuf.Message & Equatable>(_ value: T, _ hex: String) throws {
  let encoded = try value.serializedData()
  #expect(encoded.map { String(format: "%02x", $0) }.joined() == hex)
  #expect(try T(serializedBytes: encoded) == value)
}

@Test("Encrypted resource timestamps preserve absence and presence")
func encryptedResourceTimestampPresence() throws {
  // Field 6 is absent and field 7 contains a Timestamp of one second.
  let bytes: [UInt8] = [0x3a, 0x02, 0x08, 0x01]
  let removedAt = Date(timeIntervalSince1970: 1)

  let entry = try Io_Thingsdiary_V1_EncryptedEntry(serializedBytes: bytes).wire
  let topic = try Io_Thingsdiary_V1_EncryptedTopic(serializedBytes: bytes).wire
  let template = try Io_Thingsdiary_V1_EncryptedTemplate(serializedBytes: bytes).wire

  #expect(entry.deletedAt == nil)
  #expect(entry.removedAt == removedAt)
  #expect(topic.deletedAt == nil)
  #expect(topic.removedAt == removedAt)
  #expect(template.deletedAt == nil)
  #expect(template.removedAt == removedAt)
}
