import Foundation

public struct JiraProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var key: String
    public var name: String
    public var avatarUrls: AvatarURLs?

    public init(id: String, key: String, name: String, avatarUrls: AvatarURLs? = nil) {
        self.id = id
        self.key = key
        self.name = name
        self.avatarUrls = avatarUrls
    }
}
