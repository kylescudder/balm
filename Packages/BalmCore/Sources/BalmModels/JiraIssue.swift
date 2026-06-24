import Foundation

public struct JiraIssue: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var key: String
    public var summary: String
    public var descriptionText: String?
    public var descriptionADF: Data?
    public var status: JiraStatus
    public var priority: JiraPriority
    public var assignee: JiraUserSummary?
    public var reporter: JiraUserSummary?
    public var issueType: JiraIssueType
    public var created: Date?
    public var updated: Date?
    public var dueDate: String?
    public var labels: [String]
    public var components: [JiraComponent]
    public var sprint: JiraSprint?
    public var fixVersions: [JiraVersion]
    public var instanceName: String?

    public init(
        id: String,
        key: String,
        summary: String,
        descriptionText: String? = nil,
        descriptionADF: Data? = nil,
        status: JiraStatus,
        priority: JiraPriority,
        assignee: JiraUserSummary? = nil,
        reporter: JiraUserSummary? = nil,
        issueType: JiraIssueType,
        created: Date? = nil,
        updated: Date? = nil,
        dueDate: String? = nil,
        labels: [String] = [],
        components: [JiraComponent] = [],
        sprint: JiraSprint? = nil,
        fixVersions: [JiraVersion] = [],
        instanceName: String? = nil
    ) {
        self.id = id
        self.key = key
        self.summary = summary
        self.descriptionText = descriptionText
        self.descriptionADF = descriptionADF
        self.status = status
        self.priority = priority
        self.assignee = assignee
        self.reporter = reporter
        self.issueType = issueType
        self.created = created
        self.updated = updated
        self.dueDate = dueDate
        self.labels = labels
        self.components = components
        self.sprint = sprint
        self.fixVersions = fixVersions
        self.instanceName = instanceName
    }
}

public extension JiraIssue {
    /// Project key derived from `KEY-NUMBER` shape.
    var projectKey: String {
        String(key.split(separator: "-").first ?? "")
    }

    static let defaultFields: [String] = [
        "summary",
        "status",
        "description",
        "priority",
        "assignee",
        "reporter",
        "issuetype",
        "created",
        "updated",
        "duedate",
        "labels",
        "components",
        "customfield_10312",
        "fixVersions",
        "customfield_10020",
        "sprint",
        "sprints",
        "closedSprints"
    ]
}
