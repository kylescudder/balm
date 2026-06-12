import Foundation

public struct BoardColumn: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var statusKeys: [String]
    public var issues: [JiraIssue]

    public init(id: String, title: String, statusKeys: [String], issues: [JiraIssue] = []) {
        self.id = id
        self.title = title
        self.statusKeys = statusKeys
        self.issues = issues
    }
}
