import Foundation

public protocol JiraEndpoint: Sendable {
    associatedtype Response: Decodable & Sendable
    /// Build the URLRequest for this endpoint. The site cloud ID is provided by
    /// the client so endpoints don't need to know token state.
    func makeRequest(cloudId: String) throws -> URLRequest
}

public enum JiraAPIHost: Sendable {
    case rest                    // /rest/api/3
    case agile                   // /rest/agile/1.0

    func basePath(cloudId: String) -> String {
        switch self {
        case .rest: return "/ex/jira/\(cloudId)/rest/api/3"
        case .agile: return "/ex/jira/\(cloudId)/rest/agile/1.0"
        }
    }
}

public enum JiraEndpointBuilder {
    public static let scheme = "https"
    public static let host = "api.atlassian.com"

    public static func makeURL(
        host api: JiraAPIHost,
        cloudId: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = api.basePath(cloudId: cloudId) + path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw JiraError.urlConstruction(path: path)
        }
        return url
    }

    /// Ensures a Jira-supplied URL (e.g. an attachment `content`/`thumbnail` link)
    /// is routed through the OAuth gateway. The 3LO bearer is only valid against
    /// `api.atlassian.com/ex/jira/{cloudId}`. Jira already rewrites embedded links
    /// to the gateway when the issue was fetched via the gateway, so this is
    /// idempotent — a URL that already points at the gateway is returned unchanged.
    /// A site-host URL (`https://{site}.atlassian.net/rest/...`) gets re-hosted.
    public static func gatewayURL(for siteURL: URL, cloudId: String) throws -> URL {
        if siteURL.host == host { return siteURL }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/ex/jira/\(cloudId)" + siteURL.path
        components.query = siteURL.query
        guard let url = components.url else {
            throw JiraError.urlConstruction(path: siteURL.path)
        }
        return url
    }

    public static func get(
        host: JiraAPIHost,
        cloudId: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let url = try makeURL(host: host, cloudId: cloudId, path: path, queryItems: queryItems)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    public static func json(
        method: String,
        host: JiraAPIHost,
        cloudId: String,
        path: String,
        body: Encodable
    ) throws -> URLRequest {
        let url = try makeURL(host: host, cloudId: cloudId, path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        return req
    }
}

private struct AnyEncodable: Encodable {
    let wrapped: Encodable
    init(_ wrapped: Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}
