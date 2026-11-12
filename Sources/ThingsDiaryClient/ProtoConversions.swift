import Foundation
import SwiftProtobuf

extension SwiftProtobuf.Google_Protobuf_Timestamp {
  var thingsDiaryDate: Date {
    Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
  }
}

extension Io_Thingsdiary_V1_Encryption {
  init(_ value: ThingsDiaryEntityEncryption) {
    self.init()
    diaryKeyID = value.diaryKeyID
    encryptedKeyNonce = value.encryptedKeyNonce
    encryptedKeyData = value.encryptedKeyData
  }

  var model: ThingsDiaryEntityEncryption {
    ThingsDiaryEntityEncryption(
      diaryKeyID: diaryKeyID,
      encryptedKeyNonce: encryptedKeyNonce,
      encryptedKeyData: encryptedKeyData
    )
  }
}

extension Io_Thingsdiary_V1_EncryptedData {
  init(_ value: ThingsDiaryEncryptedPayload) {
    self.init()
    nonce = value.nonce
    data = value.data
  }

  var model: ThingsDiaryEncryptedPayload {
    ThingsDiaryEncryptedPayload(nonce: nonce, data: data)
  }
}

extension Io_Thingsdiary_V1_EncryptedDiary {
  var wire: WireDiary {
    WireDiary(
      id: id,
      createdAt: createdAt.thingsDiaryDate,
      updatedAt: updatedAt.thingsDiaryDate,
      encryptionKeys: encryptionKeys.map {
        WireEncryptionKey(
          value: $0.value, status: $0.status == .active ? "active" : "")
      },
      change: WireEncryptedChange(
        change: WireChange(
          id: change.change.id,
          objectID: change.change.objectID,
          parentChangeIDs: change.change.parentChangeIds,
          payload: change.change.payload
        ),
        encryption: WireDiaryEncryption(
          encryptedKeyNonce: change.encryption.encryptedKeyNonce,
          encryptedKeyData: change.encryption.encryptedKeyData
        )
      )
    )
  }
}

extension Io_Thingsdiary_V1_EncryptedEntry {
  var wire: WireEntry {
    WireEntry(
      id: id,
      diaryID: diaryID,
      createdAt: createdAt.thingsDiaryDate,
      updatedAt: updatedAt.thingsDiaryDate,
      deletedAt: hasDeletedAt ? deletedAt.thingsDiaryDate : nil,
      removedAt: hasRemovedAt ? removedAt.thingsDiaryDate : nil,
      topicID: hasTopicID ? topicID : nil,
      change: WireEntryEncryptedChange(
        change: WireChange(
          id: change.change.id,
          objectID: change.change.objectID,
          parentChangeIDs: change.change.parentChangeIds,
          payload: change.change.payload
        ),
        encryption: change.encryption.model
      )
    )
  }
}

extension Io_Thingsdiary_V1_EncryptedTopic {
  var wire: WireTopic {
    WireTopic(
      id: id,
      diaryID: diaryID,
      createdAt: createdAt.thingsDiaryDate,
      updatedAt: updatedAt.thingsDiaryDate,
      deletedAt: hasDeletedAt ? deletedAt.thingsDiaryDate : nil,
      removedAt: hasRemovedAt ? removedAt.thingsDiaryDate : nil,
      defaultTemplateID: hasDefaultTemplateID ? defaultTemplateID : nil,
      change: WireTopicEncryptedChange(
        change: WireChange(
          id: change.change.id,
          objectID: change.change.objectID,
          parentChangeIDs: change.change.parentChangeIds,
          payload: change.change.payload
        ),
        encryption: change.encryption.model
      )
    )
  }
}

extension Io_Thingsdiary_V1_EncryptedTemplate {
  var wire: WireTemplate {
    WireTemplate(
      id: id,
      diaryID: diaryID,
      version: version,
      createdAt: createdAt.thingsDiaryDate,
      updatedAt: updatedAt.thingsDiaryDate,
      deletedAt: hasDeletedAt ? deletedAt.thingsDiaryDate : nil,
      removedAt: hasRemovedAt ? removedAt.thingsDiaryDate : nil,
      encryption: encryption.model,
      details: details.model
    )
  }
}
