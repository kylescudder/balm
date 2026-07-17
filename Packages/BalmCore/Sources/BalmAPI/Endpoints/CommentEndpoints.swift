import Foundation
import BalmModels

public extension IssueEndpoints {
    /// POST /rest/api/3/issue/{key}/comment — body wrapped as a minimal ADF doc.
    /// Returns the new comment.
    struct AddComment: JiraEndpoint {
        public typealias Response = RawJiraComment
        public let issueKey: String
        public let plainText: String
        /// Rich body fragments (text + @mentions). When set, takes precedence
        /// over `plainText` so mentions become real ADF `mention` nodes.
        public let content: [CommentInline]?
        /// Media-services file IDs (UUIDs) to embed inline as `mediaSingle`
        /// nodes after the text — e.g. pasted/uploaded images.
        public let mediaFileIDs: [String]

        public init(issueKey: String, plainText: String, mediaFileIDs: [String] = []) {
            self.issueKey = issueKey
            self.plainText = plainText
            self.content = nil
            self.segments = nil
            self.mediaFileIDs = mediaFileIDs
        }

        public init(issueKey: String, content: [CommentInline], mediaFileIDs: [String] = []) {
            self.issueKey = issueKey
            self.plainText = content.plainText
            self.content = content
            self.segments = nil
            self.mediaFileIDs = mediaFileIDs
        }

        /// Block-aware body: inline runs and images interleaved in order, so
        /// pasted/dropped images render exactly where they were placed.
        public init(issueKey: String, segments: [CommentSegment]) {
            self.issueKey = issueKey
            self.plainText = segments.plainText
            self.content = nil
            self.segments = segments
            self.mediaFileIDs = []
        }

        /// Ordered text/mention/image segments. When set, supersedes both
        /// `content` and `plainText`.
        public let segments: [CommentSegment]?

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/comment"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: AnyJSON
            if let segments {
                body = adfDoc(segments: segments)
            } else if let content {
                body = adfDoc(inline: inlineNodes(from: content), mediaFileIDs: mediaFileIDs)
            } else {
                body = adfBody(text: plainText, mediaFileIDs: mediaFileIDs)
            }
            req.httpBody = try JSONEncoder().encode(["body": body])
            return req
        }
    }

    /// PUT /rest/api/3/issue/{key}/comment/{commentID}.
    struct EditComment: JiraEndpoint {
        public typealias Response = RawJiraComment
        public let issueKey: String
        public let commentID: String
        public let plainText: String

        public init(issueKey: String, commentID: String, plainText: String) {
            self.issueKey = issueKey
            self.commentID = commentID
            self.plainText = plainText
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/comment/\(commentID)"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["body": adfBody(text: plainText)])
            return req
        }
    }

    /// DELETE /rest/api/3/issue/{key}/comment/{commentID}.
    struct DeleteComment: JiraEndpoint {
        public typealias Response = EmptyResponse
        public let issueKey: String
        public let commentID: String

        public init(issueKey: String, commentID: String) {
            self.issueKey = issueKey
            self.commentID = commentID
        }

        public func makeRequest(cloudId: String) throws -> URLRequest {
            let url = try JiraEndpointBuilder.makeURL(
                host: .rest,
                cloudId: cloudId,
                path: "/issue/\(issueKey)/comment/\(commentID)"
            )
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            return req
        }
    }
}

/// Wraps plain text as a minimal ADF doc payload (returns the inner value of
/// the JSON `body` field). Same shape as `IssueFieldPatch.description(plainText:)`.
private func adfBody(text: String, mediaFileIDs: [String] = []) -> AnyJSON {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    var content: [AnyJSON] = []
    if !trimmed.isEmpty {
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        content += paragraphs.map { paragraph in
            .object([
                "type": .string("paragraph"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(paragraph)
                    ])
                ])
            ])
        }
    }

    // Each pasted/uploaded image becomes a centred mediaSingle > media node.
    for id in mediaFileIDs {
        content.append(.object([
            "type": .string("mediaSingle"),
            "attrs": .object(["layout": .string("center")]),
            "content": .array([
                .object([
                    "type": .string("media"),
                    "attrs": .object([
                        "type": .string("file"),
                        "id": .string(id),
                        "collection": .string("")
                    ])
                ])
            ])
        ]))
    }

    // A doc must have at least one block.
    if content.isEmpty {
        content = [.object([
            "type": .string("paragraph"),
            "content": .array([])
        ])]
    }

    return .object([
        "type": .string("doc"),
        "version": .int(1),
        "content": .array(content)
    ])
}

/// ADF doc from rich inline fragments (text + mentions) plus trailing media.
/// The inline nodes go in a single paragraph; images follow as `mediaSingle`.
private func adfDoc(inline: [AnyJSON], mediaFileIDs: [String]) -> AnyJSON {
    var content: [AnyJSON] = []
    if !inline.isEmpty {
        content.append(.object([
            "type": .string("paragraph"),
            "content": .array(inline)
        ]))
    }
    for id in mediaFileIDs {
        content.append(.object([
            "type": .string("mediaSingle"),
            "attrs": .object(["layout": .string("center")]),
            "content": .array([
                .object([
                    "type": .string("media"),
                    "attrs": .object([
                        "type": .string("file"),
                        "id": .string(id),
                        "collection": .string("")
                    ])
                ])
            ])
        ]))
    }
    if content.isEmpty {
        content = [.object(["type": .string("paragraph"), "content": .array([])])]
    }
    return .object([
        "type": .string("doc"),
        "version": .int(1),
        "content": .array(content)
    ])
}

/// ADF doc from ordered segments. Runs of inline content (text/mention)
/// accumulate into a paragraph; an image flushes the current paragraph and
/// emits a block-level `mediaSingle`, so images sit exactly where placed.
private func adfDoc(segments: [CommentSegment]) -> AnyJSON {
    var blocks: [AnyJSON] = []
    var inline: [AnyJSON] = []

    func flushParagraph() {
        guard !inline.isEmpty else { return }
        blocks.append(.object([
            "type": .string("paragraph"),
            "content": .array(inline)
        ]))
        inline = []
    }

    for segment in segments {
        switch segment {
        case .text(let text):
            let parts = text.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 { inline.append(.object(["type": .string("hardBreak")])) }
                if !part.isEmpty {
                    inline.append(.object(["type": .string("text"), "text": .string(part)]))
                }
            }
        case .mention(let id, let display):
            inline.append(.object([
                "type": .string("mention"),
                "attrs": .object([
                    "id": .string(id),
                    "text": .string("@\(display)")
                ])
            ]))
        case .image(let mediaFileID, let width, let height):
            flushParagraph()
            var attrs: [String: AnyJSON] = [
                "type": .string("file"),
                "id": .string(mediaFileID),
                "collection": .string("")
            ]
            // Pixel dimensions drive the rendered size in Jira — omit them
            // and the web UI shows a tiny placeholder until a manual resave.
            if let width { attrs["width"] = .int(width) }
            if let height { attrs["height"] = .int(height) }
            blocks.append(.object([
                "type": .string("mediaSingle"),
                "attrs": .object(["layout": .string("center")]),
                "content": .array([
                    .object([
                        "type": .string("media"),
                        "attrs": .object(attrs)
                    ])
                ])
            ]))
        }
    }
    flushParagraph()

    if blocks.isEmpty {
        blocks = [.object(["type": .string("paragraph"), "content": .array([])])]
    }
    return .object([
        "type": .string("doc"),
        "version": .int(1),
        "content": .array(blocks)
    ])
}

/// Turn comment fragments into ADF inline nodes. Newlines inside a text run
/// become `hardBreak` nodes; mentions become `mention` nodes carrying the
/// accountId (what triggers the Jira notification).
private func inlineNodes(from content: [CommentInline]) -> [AnyJSON] {
    content.flatMap { fragment -> [AnyJSON] in
        switch fragment {
        case .text(let text):
            let parts = text.components(separatedBy: "\n")
            var nodes: [AnyJSON] = []
            for (index, part) in parts.enumerated() {
                if index > 0 { nodes.append(.object(["type": .string("hardBreak")])) }
                if !part.isEmpty {
                    nodes.append(.object([
                        "type": .string("text"),
                        "text": .string(part)
                    ]))
                }
            }
            return nodes
        case .mention(let id, let display):
            return [.object([
                "type": .string("mention"),
                "attrs": .object([
                    "id": .string(id),
                    "text": .string("@\(display)")
                ])
            ])]
        }
    }
}
