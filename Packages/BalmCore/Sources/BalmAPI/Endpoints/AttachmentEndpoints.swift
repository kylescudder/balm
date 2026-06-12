import Foundation
import BalmModels

public extension IssueEndpoints {
    /// POST /rest/api/3/issue/{key}/attachments — multipart/form-data with one
    /// file part named `file`. Jira requires `X-Atlassian-Token: no-check`
    /// header to bypass the XSRF guard on file uploads.
    /// Returns an array of `RawJiraAttachment` (one per uploaded file).
    struct UploadAttachment: JiraEndpoint {
        public typealias Response = [RawJiraAttachment]
        public let issueKey: String
        public let data: Data
        public let filename: String
        public let mimeType: String

        public init(issueKey: String, data: Data, filename: String, mimeType: String) {
            self.issueKey = issueKey
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/attachments"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            let boundary = "Boundary-\(UUID().uuidString)"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
            req.httpBody = Self.makeMultipartBody(
                data: data,
                filename: filename,
                mimeType: mimeType,
                boundary: boundary
            )
            return req
        }

        private static func makeMultipartBody(
            data: Data,
            filename: String,
            mimeType: String,
            boundary: String
        ) -> Data {
            var body = Data()
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename(filename))\"\r\n")
            body.append("Content-Type: \(mimeType)\r\n\r\n")
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n")
            return body
        }

        /// Escape just enough so quotes and control chars don't break the header.
        private static func safeFilename(_ name: String) -> String {
            name.replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "\r", with: "_")
                .replacingOccurrences(of: "\n", with: "_")
        }
    }

    /// DELETE /rest/api/3/attachment/{id}.
    struct DeleteAttachment: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let attachmentID: String

        public init(attachmentID: String) {
            self.attachmentID = attachmentID
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/attachment/\(attachmentID)"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            return req
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
