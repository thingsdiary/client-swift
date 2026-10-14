import Foundation

public struct ThingsDiaryDiary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let createdAt: Date
    public let updatedAt: Date
    public let version: UInt64

    public init(
        id: String,
        title: String,
        description: String,
        createdAt: Date,
        updatedAt: Date,
        version: UInt64
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}

public struct ThingsDiaryPage<Item: Sendable & Equatable>: Sendable, Equatable {
    public let items: [Item]
    public let nextPageToken: String?

    public init(items: [Item], nextPageToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
    }
}

