import Foundation

public struct JiraIssueLink: Codable, Sendable, Hashable, Identifiable {
    public enum Direction: String, Codable, Sendable {
        case inward
        case outward
    }

    public struct LinkType: Codable, Sendable, Hashable {
        public var name: String
        public var inward: String
        public var outward: String

        public init(name: String, inward: String, outward: String) {
            self.name = name
            self.inward = inward
            self.outward = outward
        }
    }

    public struct LinkedIssue: Codable, Sendable, Hashable {
        public var key: String
        public var summary: String
        public var status: JiraStatus?
        public var issueType: JiraIssueType?
        public var priority: JiraPriority?

        public init(
            key: String,
            summary: String,
            status: JiraStatus? = nil,
            issueType: JiraIssueType? = nil,
            priority: JiraPriority? = nil
        ) {
            self.key = key
            self.summary = summary
            self.status = status
            self.issueType = issueType
            self.priority = priority
        }
    }

    public var id: String
    public var type: LinkType
    public var direction: Direction
    public var relationship: String
    public var issue: LinkedIssue

    public init(
        id: String,
        type: LinkType,
        direction: Direction,
        relationship: String,
        issue: LinkedIssue
    ) {
        self.id = id
        self.type = type
        self.direction = direction
        self.relationship = relationship
        self.issue = issue
    }
}

public struct JiraIssueDetails: Codable, Sendable, Hashable {
    public var attachments: [JiraAttachmentMeta]
    public var comments: [JiraComment]
    public var changelog: [JiraChangeLogItem]
    public var issueLinks: [JiraIssueLink]

    public init(
        attachments: [JiraAttachmentMeta] = [],
        comments: [JiraComment] = [],
        changelog: [JiraChangeLogItem] = [],
        issueLinks: [JiraIssueLink] = []
    ) {
        self.attachments = attachments
        self.comments = comments
        self.changelog = changelog
        self.issueLinks = issueLinks
    }
}
