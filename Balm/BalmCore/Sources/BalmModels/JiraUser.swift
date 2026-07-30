import Foundation

public struct JiraUser: Codable, Sendable, Hashable, Identifiable {
    public var accountId: String
    public var displayName: String
    public var emailAddress: String?
    public var avatarUrls: AvatarURLs?
    public var active: Bool?

    public init(
        accountId: String,
        displayName: String,
        emailAddress: String? = nil,
        avatarUrls: AvatarURLs? = nil,
        active: Bool? = nil
    ) {
        self.accountId = accountId
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.avatarUrls = avatarUrls
        self.active = active
    }

    public var id: String { accountId }
}

public struct JiraUserSummary: Codable, Sendable, Hashable {
    public var displayName: String
    public var avatarUrls: AvatarURLs?

    public init(displayName: String, avatarUrls: AvatarURLs? = nil) {
        self.displayName = displayName
        self.avatarUrls = avatarUrls
    }
}
