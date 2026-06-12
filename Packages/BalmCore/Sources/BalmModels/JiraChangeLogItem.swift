import Foundation

public struct JiraChangeLogItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var author: JiraUserSummary
    public var created: Date?
    public var items: [Entry]

    public struct Entry: Codable, Sendable, Hashable {
        public var field: String
        public var fromString: String?
        public var toString: String?

        public init(field: String, fromString: String? = nil, toString: String? = nil) {
            self.field = field
            self.fromString = fromString
            self.toString = toString
        }
    }

    public init(id: String, author: JiraUserSummary, created: Date? = nil, items: [Entry]) {
        self.id = id
        self.author = author
        self.created = created
        self.items = items
    }
}
