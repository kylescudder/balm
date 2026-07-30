import Foundation
import BalmAuth

public actor JiraClient {
    private let session: URLSession
    private let tokens: any TokenProvider
    private let decoder: JSONDecoder

    private var sprintFieldID: String?
    private var sprintFieldResolved = false
    private var instanceFieldID: String?
    private var instanceFieldResolved = false

    public init(
        tokens: any TokenProvider,
        session: URLSession = .shared,
        decoder: JSONDecoder = .jira
    ) {
        self.tokens = tokens
        self.session = session
        self.decoder = decoder
    }

    /// Resolves (and caches) this tenant's Sprint custom field id by looking for
    /// the greenhopper sprint schema. Returns `nil` if discovery fails — callers
    /// then rely on the generic per-issue customfield scan.
    public func resolveSprintFieldID() async -> String? {
        if sprintFieldResolved { return sprintFieldID }
        sprintFieldResolved = true
        do {
            let fields = try await send(ProjectEndpoints.Fields())
            sprintFieldID = fields.first {
                $0.schema?.custom == "com.pyxis.greenhopper.jira:gh-sprint"
            }?.id
        } catch {
            sprintFieldID = nil
        }
        return sprintFieldID
    }

    /// Resolves (and caches) this tenant's Instance / Database custom field id
    /// by matching the field name. Returns `nil` if discovery fails.
    public func resolveInstanceFieldID() async -> String? {
        if instanceFieldResolved { return instanceFieldID }
        instanceFieldResolved = true
        do {
            let fields = try await send(ProjectEndpoints.Fields())
            instanceFieldID = fields.first {
                $0.name?.localizedCaseInsensitiveContains("Instance") == true
            }?.id
        } catch {
            instanceFieldID = nil
        }
        return instanceFieldID
    }

    /// Seeds the cached instance field ID from an externally discovered value
    /// (e.g. from `expand=names` on a search response). No-op if already known.
    public func seedInstanceFieldID(_ id: String) {
        guard instanceFieldID == nil else { return }
        instanceFieldID = id
        instanceFieldResolved = true
    }

    public func send<E: JiraEndpoint>(_ endpoint: E) async throws -> E.Response {
        try await send(endpoint, retryOn401: true)
    }

    public func sendVoid<E: JiraEndpoint>(_ endpoint: E) async throws where E.Response == EmptyResponse {
        _ = try await send(endpoint, retryOn401: true)
    }

    private func send<E: JiraEndpoint>(_ endpoint: E, retryOn401: Bool) async throws -> E.Response {
        let auth = try await tokens.snapshot()
        var request = try endpoint.makeRequest(cloudId: auth.cloudId)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JiraError.http(status: 0, body: nil)
        }

        if http.statusCode == 401 && retryOn401 {
            await tokens.invalidateAccessToken()
            return try await send(endpoint, retryOn401: false)
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw JiraError.http(status: http.statusCode, body: body)
        }

        if E.Response.self == EmptyResponse.self {
            return EmptyResponse() as! E.Response
        }

        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw JiraError.decoding(String(describing: error))
        }
    }
}

public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

/// Per-task delegate that stops `URLSession` following redirects, so the caller
/// can read the 30x `Location` header (used to resolve media file UUIDs).
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

/// Per-task delegate that follows redirects but drops the `Authorization`
/// header when the hop leaves the Atlassian gateway. The attachment `content`
/// endpoint 302-redirects to a pre-signed `api.media.atlassian.com` URL that
/// carries its own credentials; forwarding our OAuth bearer there is rejected
/// with 401.
private final class AuthStrippingRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.host != JiraEndpointBuilder.host else { return request }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}

public extension JiraClient {
    /// Downloads the bytes at `url` (Bearer-authed) and writes them to a temp
    /// file using `suggestedFilename` so Quick Look infers the correct UTI.
    /// Returns the local file URL; the caller is responsible for cleanup.
    func downloadAttachment(url: URL, suggestedFilename: String) async throws -> URL {
        try await downloadAttachment(url: url, suggestedFilename: suggestedFilename, retryOn401: true)
    }

    private func downloadAttachment(url: URL, suggestedFilename: String, retryOn401: Bool) async throws -> URL {
        let auth = try await tokens.snapshot()
        let gatewayURL = try JiraEndpointBuilder.gatewayURL(for: url, cloudId: auth.cloudId)
        var request = URLRequest(url: gatewayURL)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (tempURL, response) = try await session.download(for: request, delegate: AuthStrippingRedirect())

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            if http.statusCode == 401 && retryOn401 {
                await tokens.invalidateAccessToken()
                return try await downloadAttachment(url: url, suggestedFilename: suggestedFilename, retryOn401: false)
            }
            throw JiraError.http(status: http.statusCode, body: nil)
        }

        let destinationDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BalmAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let destination = destinationDir.appendingPathComponent(
            "\(UUID().uuidString)-\(Self.sanitisedFilename(suggestedFilename))"
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Fetches the bytes at `url` (Bearer-authed, gateway-routed) into memory.
    /// Used to render attachment images in-app rather than downloading to disk.
    func attachmentData(url: URL) async throws -> Data {
        try await attachmentData(url: url, retryOn401: true)
    }

    private func attachmentData(url: URL, retryOn401: Bool) async throws -> Data {
        let auth = try await tokens.snapshot()
        let gatewayURL = try JiraEndpointBuilder.gatewayURL(for: url, cloudId: auth.cloudId)
        var request = URLRequest(url: gatewayURL)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request, delegate: AuthStrippingRedirect())
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 && retryOn401 {
                await tokens.invalidateAccessToken()
                return try await attachmentData(url: url, retryOn401: false)
            }
            throw JiraError.http(status: http.statusCode, body: nil)
        }
        return data
    }

    /// Resolves the Media-services file UUID for an uploaded attachment.
    /// The attachment `content` URL 30x-redirects to
    /// `api.media.atlassian.com/file/{uuid}/binary`; we read that `Location`
    /// without following it. The UUID is what an ADF `media` node needs as its
    /// `id` (the numeric attachment id is rejected as `ATTACHMENT_VALIDATION_ERROR`).
    func mediaFileID(forContentURL url: URL) async -> String? {
        guard let auth = try? await tokens.snapshot() else { return nil }
        guard let gatewayURL = try? JiraEndpointBuilder.gatewayURL(for: url, cloudId: auth.cloudId) else { return nil }
        var request = URLRequest(url: gatewayURL)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")

        let blocker = RedirectBlocker()
        guard let (_, response) = try? await session.data(for: request, delegate: blocker),
              let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let segments = URL(string: location)?.pathComponents,
              let fileIndex = segments.firstIndex(of: "file"),
              fileIndex + 1 < segments.count else {
            return nil
        }
        return segments[fileIndex + 1]
    }

    nonisolated static func sanitisedFilename(_ filename: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ".-_ ")
        return filename
            .components(separatedBy: allowed.inverted)
            .joined(separator: "_")
    }
}
