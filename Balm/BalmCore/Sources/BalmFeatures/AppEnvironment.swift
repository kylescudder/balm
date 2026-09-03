import Foundation
import Observation
import BalmAuth
import BalmAPI
import BalmModels

@MainActor
@Observable
public final class AppEnvironment {
    public enum AuthState: Sendable, Equatable {
        case loading
        case signedOut
        case signedIn(siteName: String, siteURL: URL, user: JiraUser?)
    }

    public private(set) var authState: AuthState = .loading
    public private(set) var lastError: String?

    public let oauth: AtlassianOAuth
    public let tokenStore: TokenStore
    public let api: JiraClient
    public let oauthConfig: OAuthConfig
    public let toaster: Toaster
    public let networkMonitor: NetworkMonitor
    public let activeProjectStore: ActiveProjectStore
    public let inboxStore: InboxStore
    public let projectListStore: ProjectListStore

    public init(
        oauth: AtlassianOAuth,
        tokenStore: TokenStore,
        api: JiraClient,
        oauthConfig: OAuthConfig,
        toaster: Toaster = Toaster(),
        networkMonitor: NetworkMonitor = NetworkMonitor(),
        activeProjectStore: ActiveProjectStore = ActiveProjectStore(),
        inboxStore: InboxStore? = nil
    ) {
        self.oauth = oauth
        self.tokenStore = tokenStore
        self.api = api
        self.oauthConfig = oauthConfig
        self.toaster = toaster
        self.networkMonitor = networkMonitor
        self.activeProjectStore = activeProjectStore
        // Default constructed here (rather than as a parameter default, which
        // can't reference the `api`/`networkMonitor`/`toaster` parameters
        // above) so callers that don't care about injection still get a
        // working store.
        let monitor = networkMonitor
        self.inboxStore = inboxStore ?? InboxStore(api: api, isOnline: { monitor.isOnline }, toaster: toaster)
        self.projectListStore = ProjectListStore(api: api)
    }

    public func bootstrap() async {
        do {
            guard let stored = try await tokenStore.loadCurrent() else {
                authState = .signedOut
                return
            }
            authState = .signedIn(siteName: stored.siteName, siteURL: stored.siteURL, user: nil)
            await fetchCurrentUser()
        } catch {
            lastError = error.localizedDescription
            authState = .signedOut
        }
    }

    public func signIn(anchor: ASPresentationAnchorBridge) async {
        do {
            let stored = try await oauth.start(presentationAnchor: anchor.anchor)
            try await tokenStore.save(stored)
            authState = .signedIn(siteName: stored.siteName, siteURL: stored.siteURL, user: nil)
            await fetchCurrentUser()
        } catch AuthError.userCancelled {
            // silent
        } catch let urlError as URLError {
            lastError = friendlyURLErrorMessage(urlError)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func friendlyURLErrorMessage(_ error: URLError) -> String {
        let endpoint = oauthConfig.tokenExchangeEndpoint.absoluteString
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
            return "Could not reach the Balm backend at \(endpoint). "
                + "Check that the backend is running and reachable over HTTPS."
        case .notConnectedToInternet:
            return "No network connection."
        default:
            return "\(error.localizedDescription) (\(endpoint))"
        }
    }

    public func signOut() async {
        do {
            try await tokenStore.signOut()
        } catch {
            lastError = error.localizedDescription
        }
        // Forget the user's active project — next sign-in starts fresh.
        activeProjectStore.set(nil)
        projectListStore.reset()
        ProjectAvatarCache.shared.reset()
        inboxStore.stopAndReset()
        authState = .signedOut
    }

    public func fetchCurrentUser() async {
        do {
            let user = try await api.send(UserEndpoints.Myself())
            if case .signedIn(let siteName, let siteURL, _) = authState {
                authState = .signedIn(siteName: siteName, siteURL: siteURL, user: user)
            }
            inboxStore.start(accountId: user.accountId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Retries `fetchCurrentUser()` if it never succeeded — e.g. a transient
    /// failure (offline, 5xx) at launch that left `authState`'s `user` nil and
    /// `inboxStore` never started. Nothing else retries that call, so without
    /// this the inbox stays dead for the rest of the session even after
    /// connectivity returns. Called from the scenePhase-active hook that
    /// already re-syncs the inbox on foreground; a no-op once the user has
    /// loaded.
    public func fetchCurrentUserIfNeeded() async {
        guard case .signedIn(_, _, let user) = authState, user == nil else { return }
        await fetchCurrentUser()
    }
}

public extension AppEnvironment {
    /// Reads `ATLASSIAN_CLIENT_ID` from the main bundle's Info.plist.
    /// Falls back to an empty string so the UI can prompt for configuration.
    static func defaultClientID() -> String {
        Bundle.main.object(forInfoDictionaryKey: "ATLASSIAN_CLIENT_ID") as? String ?? ""
    }

    /// Reads `BALM_BFF_BASE_URL` from Info.plist. Falls back to localhost for dev.
    static func defaultBFFBaseURL() -> URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "BALM_BFF_BASE_URL") as? String
        if let raw, let url = URL(string: raw) { return url }
        return URL(string: "http://localhost:3000")!
    }

    static func live() -> AppEnvironment {
        let config = OAuthConfig.atlassian(
            clientID: defaultClientID(),
            bffBaseURL: defaultBFFBaseURL()
        )
        let oauth = AtlassianOAuth(config: config)
        let keychain = KeychainStore.live
        let tokenStore = TokenStore(keychain: keychain, refresher: oauth)
        let api = JiraClient(tokens: tokenStore)
        let networkMonitor = NetworkMonitor()
        let toaster = Toaster()
        let inboxStore = InboxStore(api: api, isOnline: { networkMonitor.isOnline }, toaster: toaster)
        return AppEnvironment(
            oauth: oauth,
            tokenStore: tokenStore,
            api: api,
            oauthConfig: config,
            toaster: toaster,
            networkMonitor: networkMonitor,
            inboxStore: inboxStore
        )
    }
}
