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

    public init(
        oauth: AtlassianOAuth,
        tokenStore: TokenStore,
        api: JiraClient,
        oauthConfig: OAuthConfig,
        toaster: Toaster = Toaster(),
        networkMonitor: NetworkMonitor = NetworkMonitor(),
        activeProjectStore: ActiveProjectStore = ActiveProjectStore()
    ) {
        self.oauth = oauth
        self.tokenStore = tokenStore
        self.api = api
        self.oauthConfig = oauthConfig
        self.toaster = toaster
        self.networkMonitor = networkMonitor
        self.activeProjectStore = activeProjectStore
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
                + "Make sure the Next.js dev server is running (cd jira-clone-ref && bun dev) "
                + "and that ATLASSIAN_CLIENT_ID + ATLASSIAN_CLIENT_SECRET are set in .env.local."
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
        authState = .signedOut
    }

    public func fetchCurrentUser() async {
        do {
            let user = try await api.send(UserEndpoints.Myself())
            if case .signedIn(let siteName, let siteURL, _) = authState {
                authState = .signedIn(siteName: siteName, siteURL: siteURL, user: user)
            }
        } catch {
            lastError = error.localizedDescription
        }
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
        return AppEnvironment(oauth: oauth, tokenStore: tokenStore, api: api, oauthConfig: config)
    }
}
