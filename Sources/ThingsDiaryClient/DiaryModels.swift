import Foundation

public struct ThingsDiaryCreateParams: Sendable, Equatable {
    public let title: String
    public let description: String

    public init(title: String, description: String) {
        self.title = title
        self.description = description
    }
}

public struct ThingsDiaryDiaryParams: Sendable, Equatable {
    public let title: String
    public let description: String

    public init(title: String, description: String) {
        self.title = title
        self.description = description
    }
}

public struct ThingsDiaryPutParams: Sendable, Equatable {
    public let title: String
    public let description: String
    public let version: UInt64

    public init(title: String, description: String, version: UInt64) {
        self.title = title
        self.description = description
        self.version = version
    }
}

public enum ThingsDiaryEncryptionKeyStatus: String, Sendable, Equatable, Codable {
    case active
    case rotating
    case rotated
}

public struct ThingsDiaryEncryptionKey: Sendable, Equatable {
    public let id: String
    public let value: Data
    public let status: ThingsDiaryEncryptionKeyStatus

    public init(id: String, value: Data, status: ThingsDiaryEncryptionKeyStatus) {
        self.id = id
        self.value = value
        self.status = status
    }
}

public enum ThingsDiaryChangeOperation: String, Sendable, Equatable, Codable {
    case created
    case updated
    case softDeleted = "soft_deleted"
    case removed
}

public enum ThingsDiaryChangeEntityType: String, Sendable, Equatable, Codable {
    case diary
    case entry
    case topic
    case template
}

public struct ThingsDiaryChange: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let createdAt: Date
    public let operation: ThingsDiaryChangeOperation
    public let entityType: ThingsDiaryChangeEntityType
    public let entityID: String

    public init(id: String, createdAt: Date, operation: ThingsDiaryChangeOperation, entityType: ThingsDiaryChangeEntityType, entityID: String) {
        self.id = id
        self.createdAt = createdAt
        self.operation = operation
        self.entityType = entityType
        self.entityID = entityID
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt = "created_at", operation
        case entityType = "entity_type", entityID = "entity_id"
    }
}

public struct ThingsDiaryChangesPage: Sendable, Equatable {
    public let changes: [ThingsDiaryChange]
    public let nextPageToken: String?

    public init(changes: [ThingsDiaryChange], nextPageToken: String?) {
        self.changes = changes
        self.nextPageToken = nextPageToken
    }
}
