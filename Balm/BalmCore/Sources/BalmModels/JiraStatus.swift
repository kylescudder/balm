import Foundation

public struct JiraStatus: Codable, Sendable, Hashable {
    public var name: String
    public var statusCategory: JiraStatusCategory

    public init(name: String, statusCategory: JiraStatusCategory) {
        self.name = name
        self.statusCategory = statusCategory
    }
}

public struct JiraStatusCategory: Codable, Sendable, Hashable {
    public var key: String
    public var colorName: String

    public init(key: String, colorName: String) {
        self.key = key
        self.colorName = colorName
    }
}

public struct JiraPriority: Codable, Sendable, Hashable {
    public var name: String
    public var iconUrl: URL?

    public init(name: String, iconUrl: URL? = nil) {
        self.name = name
        self.iconUrl = iconUrl
    }
}

public struct JiraIssueType: Codable, Sendable, Hashable, Identifiable {
    public var id: String?
    public var name: String
    public var iconUrl: URL?
    public var subtask: Bool?

    public init(id: String? = nil, name: String, iconUrl: URL? = nil, subtask: Bool? = nil) {
        self.id = id
        self.name = name
        self.iconUrl = iconUrl
        self.subtask = subtask
    }
}

public struct JiraTransition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var to: JiraStatus

    public init(id: String, name: String, to: JiraStatus) {
        self.id = id
        self.name = name
        self.to = to
    }
}
