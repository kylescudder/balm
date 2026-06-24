import Foundation

public struct FilterOptions: Codable, Sendable, Hashable {
    public var status: [String]
    public var priority: [String]
    public var assignee: [String]
    public var issueType: [String]
    public var labels: [String]
    public var components: [String]
    public var reporter: [String]
    public var sprint: [String]
    public var release: [String]
    public var dueDateFrom: String?
    public var dueDateTo: String?
    public var instanceName: [String]

    public init(
        status: [String] = [],
        priority: [String] = [],
        assignee: [String] = [],
        issueType: [String] = [],
        labels: [String] = [],
        components: [String] = [],
        reporter: [String] = [],
        sprint: [String] = [],
        release: [String] = [],
        dueDateFrom: String? = nil,
        dueDateTo: String? = nil,
        instanceName: [String] = []
    ) {
        self.status = status
        self.priority = priority
        self.assignee = assignee
        self.issueType = issueType
        self.labels = labels
        self.components = components
        self.reporter = reporter
        self.sprint = sprint
        self.release = release
        self.dueDateFrom = dueDateFrom
        self.dueDateTo = dueDateTo
        self.instanceName = instanceName
    }

    public static let empty = FilterOptions()

    public var isEmpty: Bool {
        status.isEmpty
            && priority.isEmpty
            && assignee.isEmpty
            && issueType.isEmpty
            && labels.isEmpty
            && components.isEmpty
            && reporter.isEmpty
            && release.isEmpty
            && instanceName.isEmpty
            && dueDateFrom == nil
            && dueDateTo == nil
    }

    /// Counts each active section as one active filter (not each value).
    /// Sprint is excluded because it is required, not a discretionary filter.
    public var activeCount: Int {
        var n = 0
        if !status.isEmpty { n += 1 }
        if !priority.isEmpty { n += 1 }
        if !assignee.isEmpty { n += 1 }
        if !issueType.isEmpty { n += 1 }
        if !labels.isEmpty { n += 1 }
        if !components.isEmpty { n += 1 }
        if !reporter.isEmpty { n += 1 }
        if !release.isEmpty { n += 1 }
        if !instanceName.isEmpty { n += 1 }
        if dueDateFrom != nil || dueDateTo != nil { n += 1 }
        return n
    }
}

public extension FilterOptions {
    static let unassignedSentinel = "UNASSIGNED"
}
