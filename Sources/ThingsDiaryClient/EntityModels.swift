import Foundation

public struct ThingsDiaryEntryParams: Codable, Sendable, Equatable {
  public let content: String
  public let topicID: String?
  public let archived: Bool
  public let bookmarked: Bool
  public let previewHidden: Bool

  public init(
    content: String,
    topicID: String? = nil,
    archived: Bool = false,
    bookmarked: Bool = false,
    previewHidden: Bool = false
  ) {
    self.content = content
    self.topicID = topicID
    self.archived = archived
    self.bookmarked = bookmarked
    self.previewHidden = previewHidden
  }

  enum CodingKeys: String, CodingKey {
    case content, archived, bookmarked
    case topicID = "topic_id"
    case previewHidden = "preview_hidden"
  }
}

/// Encrypted entity details in the zero-knowledge API envelope.
public struct ThingsDiaryEncryptedPayload: Codable, Sendable, Equatable {
  public let nonce: Data
  public let data: Data

  public init(nonce: Data, data: Data) {
    self.nonce = nonce
    self.data = data
  }
}

/// Encrypted per-entity key metadata returned by the API.
public struct ThingsDiaryEntityEncryption: Codable, Sendable, Equatable {
  public let diaryKeyID: String
  public let encryptedKeyNonce: Data
  public let encryptedKeyData: Data

  public init(diaryKeyID: String, encryptedKeyNonce: Data, encryptedKeyData: Data) {
    self.diaryKeyID = diaryKeyID
    self.encryptedKeyNonce = encryptedKeyNonce
    self.encryptedKeyData = encryptedKeyData
  }

  enum CodingKeys: String, CodingKey {
    case diaryKeyID = "diary_key_id"
    case encryptedKeyNonce = "encrypted_key_nonce"
    case encryptedKeyData = "encrypted_key_data"
  }
}

public struct ThingsDiaryEntry: Sendable, Equatable, Identifiable {
  public let id: String
  public let diaryID: String
  public let content: String
  public let topicID: String?
  public let archived: Bool
  public let bookmarked: Bool
  public let previewHidden: Bool
  public let createdAt: Date
  public let updatedAt: Date
  public let deletedAt: Date?
  public let version: UInt64

  public init(
    id: String,
    diaryID: String,
    content: String,
    topicID: String? = nil,
    archived: Bool = false,
    bookmarked: Bool = false,
    previewHidden: Bool = false,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    version: UInt64
  ) {
    self.id = id
    self.diaryID = diaryID
    self.content = content
    self.topicID = topicID
    self.archived = archived
    self.bookmarked = bookmarked
    self.previewHidden = previewHidden
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.version = version
  }
}

struct WireEntry: Codable, Sendable, Equatable {
  public let id: String
  public let diaryID: String
  public let version: UInt64
  public let createdAt: Date
  public let updatedAt: Date
  public let deletedAt: Date?
  public let topicID: String?
  public let encryption: ThingsDiaryEntityEncryption
  public let details: ThingsDiaryEncryptedPayload

  init(
    id: String,
    diaryID: String,
    version: UInt64,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    topicID: String? = nil,
    encryption: ThingsDiaryEntityEncryption,
    details: ThingsDiaryEncryptedPayload
  ) {
    self.id = id
    self.diaryID = diaryID
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.topicID = topicID
    self.encryption = encryption
    self.details = details
  }

  enum CodingKeys: String, CodingKey {
    case id, version, encryption, details
    case diaryID = "diary_id"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case deletedAt = "deleted_at"
    case topicID = "topic_id"
  }
}

public struct ThingsDiaryTopicParams: Sendable, Equatable {
  public let title: String
  public let description: String
  public let color: String
  public let entryPreviewable: Bool
  public let defaultTemplateID: String?

  public init(
    title: String,
    description: String,
    color: String,
    entryPreviewable: Bool = true,
    defaultTemplateID: String? = nil
  ) {
    self.title = title
    self.description = description
    self.color = color
    self.entryPreviewable = entryPreviewable
    self.defaultTemplateID = defaultTemplateID
  }
}

public struct ThingsDiaryTopic: Sendable, Equatable, Identifiable {
  public let id: String
  public let diaryID: String
  public let title: String
  public let description: String
  public let color: String
  public let entryPreviewable: Bool
  public let defaultTemplateID: String?
  public let createdAt: Date
  public let updatedAt: Date
  public let deletedAt: Date?
  public let version: UInt64

  public init(
    id: String,
    diaryID: String,
    title: String,
    description: String,
    color: String,
    entryPreviewable: Bool = true,
    defaultTemplateID: String? = nil,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    version: UInt64
  ) {
    self.id = id
    self.diaryID = diaryID
    self.title = title
    self.description = description
    self.color = color
    self.entryPreviewable = entryPreviewable
    self.defaultTemplateID = defaultTemplateID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.version = version
  }
}

struct WireTopic: Codable, Sendable, Equatable {
  public let id: String
  public let diaryID: String
  public let version: UInt64
  public let createdAt: Date
  public let updatedAt: Date
  public let deletedAt: Date?
  public let defaultTemplateID: String?
  public let encryption: ThingsDiaryEntityEncryption
  public let details: ThingsDiaryEncryptedPayload

  public init(
    id: String,
    diaryID: String,
    version: UInt64,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    defaultTemplateID: String? = nil,
    encryption: ThingsDiaryEntityEncryption,
    details: ThingsDiaryEncryptedPayload
  ) {
    self.id = id
    self.diaryID = diaryID
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.defaultTemplateID = defaultTemplateID
    self.encryption = encryption
    self.details = details
  }

  enum CodingKeys: String, CodingKey {
    case id, version, encryption, details
    case diaryID = "diary_id"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case deletedAt = "deleted_at"
    case defaultTemplateID = "default_template_id"
  }
}

public struct ThingsDiaryTemplateParams: Sendable, Equatable {
  public let content: String

  public init(content: String) {
    self.content = content
  }
}

public struct ThingsDiaryTemplate: Sendable, Equatable, Identifiable {
  public let id: String
  public let diaryID: String
  public let content: String
  public let createdAt: Date
  public let updatedAt: Date
  public let deletedAt: Date?
  public let version: UInt64

  public init(
    id: String,
    diaryID: String,
    content: String,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    version: UInt64
  ) {
    self.id = id
    self.diaryID = diaryID
    self.content = content
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.version = version
  }
}

struct WireTemplate: Codable, Sendable, Equatable {
  public let id: String
  public let diaryID: String
  public let version: UInt64
  public let createdAt: Date
  public let updatedAt: Date
  public let deletedAt: Date?
  public let encryption: ThingsDiaryEntityEncryption
  public let details: ThingsDiaryEncryptedPayload

  public init(
    id: String,
    diaryID: String,
    version: UInt64,
    createdAt: Date,
    updatedAt: Date,
    deletedAt: Date? = nil,
    encryption: ThingsDiaryEntityEncryption,
    details: ThingsDiaryEncryptedPayload
  ) {
    self.id = id
    self.diaryID = diaryID
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
    self.encryption = encryption
    self.details = details
  }

  enum CodingKeys: String, CodingKey {
    case id, version, encryption, details
    case diaryID = "diary_id"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case deletedAt = "deleted_at"
  }
}
