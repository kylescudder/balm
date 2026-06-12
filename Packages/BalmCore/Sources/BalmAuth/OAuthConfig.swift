import Foundation

public struct OAuthConfig: Sendable, Equatable {
    public var clientID: String
    public var redirectURI: URL
    public var authorizationEndpoint: URL
    public var tokenExchangeEndpoint: URL
    public var tokenRefreshEndpoint: URL
    public var audience: String
    public var scopes: [String]

    public init(
        clientID: String,
        redirectURI: URL,
        authorizationEndpoint: URL,
        tokenExchangeEndpoint: URL,
        tokenRefreshEndpoint: URL,
        audience: String,
        scopes: [String]
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenExchangeEndpoint = tokenExchangeEndpoint
        self.tokenRefreshEndpoint = tokenRefreshEndpoint
        self.audience = audience
        self.scopes = scopes
    }

    /// Atlassian 3LO configuration with token exchange routed through the
    /// Balm BFF (the existing Next.js app). Atlassian requires `client_secret`
    /// on `/oauth/token` even when PKCE is in use, so the secret stays on the
    /// server; the BFF returns a token bundle plus resolved Jira site identity.
    public static func atlassian(clientID: String, bffBaseURL: URL) -> OAuthConfig {
        OAuthConfig(
            clientID: clientID,
            redirectURI: URL(string: "balm://auth/callback")!,
            authorizationEndpoint: URL(string: "https://auth.atlassian.com/authorize")!,
            tokenExchangeEndpoint: bffBaseURL.appendingPathComponent("api/auth/native/exchange"),
            tokenRefreshEndpoint: bffBaseURL.appendingPathComponent("api/auth/native/refresh"),
            audience: "api.atlassian.com",
            // Full GRANULAR scope set. This OAuth app uses granular (not classic)
            // scopes, and Atlassian forbids mixing the two — so every scope here
            // is granular. Each must also be enabled on the app in the developer
            // console (Permissions → Jira platform REST API / Jira Software API).
            // Derived from Atlassian's OpenAPI spec — the exact granular scope
            // union across every endpoint Balm calls. Endpoints like
            // `/search/jql` and `/project/search` require several granular
            // scopes each; an incomplete set yields "scope does not match".
            scopes: [
                // Jira platform — read
                "read:issue:jira",
                "read:issue-meta:jira",
                "read:issue-details:jira",
                "read:issue-security-level:jira",
                "read:issue.vote:jira",
                "read:issue.changelog:jira",
                "read:issue.transition:jira",
                "read:status:jira",
                "read:field:jira",
                "read:field-configuration:jira",
                "read:audit-log:jira",
                "read:avatar:jira",
                "read:comment:jira",
                "read:comment.property:jira",
                "read:issue-link:jira",
                "read:issue-link-type:jira",
                "read:issue-type:jira",
                "read:issue-type-hierarchy:jira",
                "read:priority:jira",
                "read:label:jira",
                "read:project:jira",
                "read:project-category:jira",
                "read:project-role:jira",
                "read:project-version:jira",
                "read:project.component:jira",
                "read:project.property:jira",
                "read:user:jira",
                "read:group:jira",
                "read:application-role:jira",
                "read:attachment:jira",
                // Jira platform — write / delete
                "write:issue:jira",
                "write:issue.property:jira",
                "write:comment:jira",
                "write:comment.property:jira",
                "write:attachment:jira",
                "write:issue-link:jira",
                "delete:comment:jira",
                "delete:comment.property:jira",
                "delete:attachment:jira",
                "delete:issue-link:jira",
                // Jira Software (agile) — boards & sprints
                "read:board-scope:jira-software",
                "read:sprint:jira-software",
                "write:sprint:jira-software",
                "write:board-scope:jira-software",
                // Refresh tokens
                "offline_access"
            ]
        )
    }
}

public extension OAuthConfig {
    static let callbackScheme = "balm"
}
