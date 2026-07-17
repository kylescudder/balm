import Foundation

/// Public read-only view of authentication state. Sendable snapshot for cross-actor use.
public struct AuthSnapshot: Sendable, Equatable {
    public let accessToken: String
    public let cloudId: String
    public let siteName: String
    public let siteURL: URL
}

/// Protocol that `JiraClient` and other API consumers depend on.
/// Implemented by `TokenStore`; mockable in tests.
public protocol TokenProvider: Sendable {
    func snapshot() async throws -> AuthSnapshot
    func invalidateAccessToken() async
}

public protocol AuthRefresher: Sendable {
    func refresh(refreshToken: String) async throws -> TokenResponse
}

extension AtlassianOAuth: AuthRefresher {}

public extension Notification.Name {
    /// Posted (once per dead session) when a token refresh is rejected
    /// outright — the refresh token is permanently invalid and the app
    /// should sign the user out rather than keep surfacing raw errors.
    static let balmSessionExpired = Notification.Name("app.balm.sessionExpired")
}

/// Owns Keychain-backed auth state. Coalesces concurrent refreshes via a single-flight task.
public actor TokenStore: TokenProvider {
    private let keychain: KeychainStore
    private let refresher: AuthRefresher
    private var cached: StoredAuth?
    private var inflightRefresh: Task<StoredAuth, Error>?
    /// Guards against a burst of failing API calls posting `.balmSessionExpired`
    /// repeatedly before the sign-out lands. Reset on save/sign-out.
    private var announcedSessionExpiry = false

    public init(keychain: KeychainStore, refresher: AuthRefresher) {
        self.keychain = keychain
        self.refresher = refresher
    }

    public func loadCurrent() async throws -> StoredAuth? {
        if let cached { return cached }
        let stored: StoredAuth? = try keychain.load(StoredAuth.self)
        cached = stored
        return stored
    }

    public func save(_ auth: StoredAuth) async throws {
        try keychain.save(auth)
        cached = auth
        announcedSessionExpiry = false
    }

    public func signOut() async throws {
        try keychain.delete()
        cached = nil
        inflightRefresh?.cancel()
        inflightRefresh = nil
        announcedSessionExpiry = false
    }

    public func snapshot() async throws -> AuthSnapshot {
        let auth = try await ensureValid()
        return AuthSnapshot(
            accessToken: auth.accessToken,
            cloudId: auth.cloudId,
            siteName: auth.siteName,
            siteURL: auth.siteURL
        )
    }

    public func invalidateAccessToken() async {
        guard var current = cached else { return }
        current.accessTokenExpiresAt = .distantPast
        cached = current
    }

    // MARK: - Internals

    private func ensureValid() async throws -> StoredAuth {
        guard let current = try await loadCurrent() else {
            throw AuthError.refreshFailed(reason: "not signed in")
        }
        if current.isAccessTokenStillValid { return current }
        return try await coalescedRefresh(using: current)
    }

    private func coalescedRefresh(using current: StoredAuth) async throws -> StoredAuth {
        if let inflightRefresh {
            return try await inflightRefresh.value
        }
        let task = Task { [refresher, keychain] in
            let response = try await refresher.refresh(refreshToken: current.refreshToken)
            guard !response.accessToken.isEmpty else {
                throw AuthError.missingTokenInResponse
            }
            let next = StoredAuth(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? current.refreshToken,
                accessTokenExpiresAt: Date().addingTimeInterval(response.expiresIn ?? 3600),
                cloudId: current.cloudId,
                siteName: current.siteName,
                siteURL: current.siteURL,
                scopes: response.scope?.split(separator: " ").map(String.init) ?? current.scopes
            )
            try keychain.save(next)
            return next
        }
        inflightRefresh = task
        let refreshed: StoredAuth
        do {
            refreshed = try await task.value
        } catch {
            inflightRefresh = nil
            if case AuthError.sessionExpired = error, !announcedSessionExpiry {
                announcedSessionExpiry = true
                Task { @MainActor in
                    NotificationCenter.default.post(name: .balmSessionExpired, object: nil)
                }
            }
            throw error
        }
        inflightRefresh = nil
        cached = refreshed
        return refreshed
    }
}
