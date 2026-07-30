import Foundation

public struct StoredAuth: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date
    public var cloudId: String
    public var siteName: String
    public var siteURL: URL
    public var scopes: [String]

    public init(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAt: Date,
        cloudId: String,
        siteName: String,
        siteURL: URL,
        scopes: [String]
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.cloudId = cloudId
        self.siteName = siteName
        self.siteURL = siteURL
        self.scopes = scopes
    }

    public var isAccessTokenStillValid: Bool {
        accessTokenExpiresAt.timeIntervalSinceNow > 30
    }
}

public struct AccessibleResource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var url: URL
    public var scopes: [String]
    public var avatarUrl: URL?

    public init(id: String, name: String, url: URL, scopes: [String], avatarUrl: URL? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.scopes = scopes
        self.avatarUrl = avatarUrl
    }
}
