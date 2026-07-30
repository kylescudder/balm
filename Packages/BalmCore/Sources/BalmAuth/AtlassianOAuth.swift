import Foundation
import AuthenticationServices

/// Wraps `ASWebAuthenticationSession` for Atlassian 3LO.
///
/// Token exchange and refresh are routed through the Balm BFF — Atlassian's
/// `/oauth/token` requires `client_secret`, so the secret stays on the server.
/// The BFF returns the access/refresh tokens plus the resolved
/// `cloudId`, `siteName`, and `siteURL` for the first accessible Jira site.
public final class AtlassianOAuth: NSObject, Sendable {
    private let config: OAuthConfig
    private let urlSession: URLSession

    public init(config: OAuthConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    @MainActor
    public func start(presentationAnchor: ASPresentationAnchor) async throws -> StoredAuth {
        let state = UUID().uuidString
        let authURL = try buildAuthorizationURL(state: state)

        let callbackURL = try await runWebAuth(url: authURL, anchor: presentationAnchor)
        let code = try extractCode(from: callbackURL, expectedState: state)
        return try await exchangeCode(code)
    }

    public func refresh(refreshToken: String) async throws -> TokenResponse {
        let payload = ["refresh_token": refreshToken]
        let data = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: config.tokenRefreshEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data

        let (body, response) = try await urlSession.data(for: request)
        // A 4xx rejection of a refresh (Atlassian's invalid_grant /
        // unauthorized_client passed through by the BFF) means the rotating
        // refresh token is permanently dead — revoked, expired after 90 days
        // of inactivity, or invalidated by reuse detection. Retrying can
        // never succeed, so surface it distinctly from transient failures.
        if let http = response as? HTTPURLResponse, [400, 401, 403].contains(http.statusCode) {
            throw AuthError.sessionExpired
        }
        try Self.assertOK(response, data: body)
        return try Self.decoder.decode(TokenResponse.self, from: body)
    }

    // MARK: - Internals

    private func buildAuthorizationURL(state: String) throws -> URL {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "audience", value: config.audience),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components?.url else { throw AuthError.configurationMissing("authorize URL") }
        return url
    }

    /// Nonisolated by design — `ASWebAuthenticationSession` invokes its completion
    /// from a non-main queue, and if this method (or the closure) is `@MainActor`,
    /// the Swift 6 runtime asserts on the actor mismatch (`dispatch_assert_queue_fail`).
    /// The session itself is `@MainActor`, so its construction and `start()` happen
    /// inside an explicit `Task { @MainActor in ... }`.
    private func runWebAuth(url: URL, anchor: ASPresentationAnchor) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let anchorBox = AnchorBox(anchor: anchor)
            let scheme = OAuthConfig.callbackScheme
            let completion = Self.makeCompletionHandler(continuation: continuation)

            Task { @MainActor in
                let contextProvider = WebAuthAnchor(anchor: anchorBox.anchor)
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: scheme,
                    completionHandler: completion(contextProvider)
                )
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = contextProvider
                if !session.start() {
                    continuation.resume(throwing: AuthError.invalidCallbackURL)
                }
            }
        }
    }

    private static func makeCompletionHandler(
        continuation: CheckedContinuation<URL, Error>
    ) -> @Sendable (WebAuthAnchor) -> @Sendable (URL?, Error?) -> Void {
        { keepAlive in
            { callback, error in
                _ = keepAlive
                if let error {
                    if let err = error as? ASWebAuthenticationSessionError, err.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: AuthError.invalidCallbackURL)
                    return
                }
                continuation.resume(returning: callback)
            }
        }
    }

    private func extractCode(from url: URL, expectedState: String) throws -> String {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else {
            throw AuthError.invalidCallbackURL
        }
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else { throw AuthError.stateMismatch }
        if let errorParam = items.first(where: { $0.name == "error" })?.value {
            throw AuthError.refreshFailed(reason: errorParam)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthError.missingCode
        }
        return code
    }

    private func exchangeCode(_ code: String) async throws -> StoredAuth {
        let payload: [String: String] = [
            "code": code,
            "redirect_uri": config.redirectURI.absoluteString
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: config.tokenExchangeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data

        let (body, response) = try await urlSession.data(for: request)
        try Self.assertOK(response, data: body)

        let bundle = try Self.decoder.decode(NativeExchangeResponse.self, from: body)
        guard !bundle.accessToken.isEmpty else { throw AuthError.missingTokenInResponse }
        guard let siteURL = URL(string: bundle.siteUrl) else {
            throw AuthError.decoding("Invalid site_url returned by BFF")
        }

        return StoredAuth(
            accessToken: bundle.accessToken,
            refreshToken: bundle.refreshToken ?? "",
            accessTokenExpiresAt: Date().addingTimeInterval(bundle.expiresIn ?? 3600),
            cloudId: bundle.cloudId,
            siteName: bundle.siteName,
            siteURL: siteURL,
            scopes: bundle.scope?.split(separator: " ").map(String.init) ?? config.scopes
        )
    }

    private static func assertOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.http(status: 0, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw AuthError.http(status: http.statusCode, body: body)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

public struct TokenResponse: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresIn: TimeInterval?
    public var tokenType: String?
    public var scope: String?
}

private struct NativeExchangeResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?
    let tokenType: String?
    let cloudId: String
    let siteName: String
    let siteUrl: String
    let scopes: [String]?
}

/// Holds an `ASPresentationAnchor` so it can ride across actor boundaries.
/// Anchor is only ever read on the main actor in `WebAuthAnchor.presentationAnchor`.
private final class AnchorBox: @unchecked Sendable {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
}

/// Strong context provider for `ASWebAuthenticationSession`'s weak property.
/// Not isolated to an actor — system invokes `presentationAnchor(for:)` on main itself.
final class WebAuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
