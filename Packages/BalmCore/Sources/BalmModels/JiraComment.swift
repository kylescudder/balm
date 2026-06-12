import Foundation

public struct JiraComment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var author: JiraUserSummary
    public var created: Date?
    public var updated: Date?
    public var body: String
    public var bodyADF: Data?

    public init(
        id: String,
        author: JiraUserSummary,
        created: Date? = nil,
        updated: Date? = nil,
        body: String,
        bodyADF: Data? = nil
    ) {
        self.id = id
        self.author = author
        self.created = created
        self.updated = updated
        self.body = body
        self.bodyADF = bodyADF
    }
}
