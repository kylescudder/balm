import Foundation
import BalmModels

/// Raw payloads carried inside a Jira issue when fetched with
/// `expand=changelog,renderedFields` and `fields=*all`.

public struct RawJiraComment: Decodable, Sendable {
    public let id: String
    public let author: JiraUserSummary
    public let created: Date?
    public let updated: Date?
    public let body: BodyEnvelope?
    public let renderedBody: String?

    public struct BodyEnvelope: Decodable, Sendable {
        public let raw: Data

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                self.raw = Data()
                return
            }
            if let s = try? c.decode(String.self) {
                self.raw = Data(s.utf8)
                return
            }
            let any = try c.decode(AnyJSON.self)
            self.raw = try JSONEncoder().encode(any)
        }
    }
}

public struct RawJiraCommentsPage: Decodable, Sendable {
    public let comments: [RawJiraComment]
}

public struct RawJiraAttachment: Decodable, Sendable {
    public let id: String
    public let filename: String
    public let size: Int
    public let mimeType: String?
    public let content: URL?
    public let thumbnail: URL?
    public let created: Date?
}

public struct RawJiraChangelogPage: Decodable, Sendable {
    public let histories: [RawJiraChangelogEntry]
}

public struct RawJiraChangelogEntry: Decodable, Sendable {
    public let id: String
    public let author: JiraUserSummary
    public let created: Date?
    public let items: [JiraChangeLogItem.Entry]
}

public struct RawJiraIssueLink: Decodable, Sendable {
    public let id: String
    public let type: JiraIssueLink.LinkType
    public let inwardIssue: LinkedIssue?
    public let outwardIssue: LinkedIssue?

    public struct LinkedIssue: Decodable, Sendable {
        public let id: String?
        public let key: String
        public let fields: LinkedFields?
    }

    public struct LinkedFields: Decodable, Sendable {
        public let summary: String?
        public let status: JiraStatus?
        public let issuetype: JiraIssueType?
        public let priority: JiraPriority?
    }
}
