import Foundation
import BalmModels

/// Rendered block-level output. Inline runs are baked into `AttributedString`s.
/// Render with `ADFBlockView` (in BalmFeatures).
public indirect enum ADFBlock: Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case bulletList([[ADFBlock]])      // each entry is one list item (which can contain blocks)
    case orderedList([[ADFBlock]])
    case codeBlock(language: String?, String)
    case quote([ADFBlock])
    case image(ADFImage)
    case attachmentRef(id: String, filename: String?)
    case table([[[ADFBlock]]])         // rows × cells × blocks
    case rule
    case unknown(type: String)
}

/// An inline image resolved from an ADF `media` or legacy `image` node.
///
/// When `attachment` is set the bytes live behind Jira's attachment endpoint
/// and must be fetched through the authenticated API layer; a plain
/// `AsyncImage` against `url` gets a 401 and never renders. When it is nil the
/// URL is an ordinary public resource and needs no credentials.
public struct ADFImage: Sendable {
    public var url: URL
    public var alt: String?
    /// The Jira attachment this node resolved to, if any.
    public var attachment: JiraAttachmentMeta?
    /// Pixel width reported by the ADF node, so small images are not upscaled
    /// to fill the column.
    public var naturalWidth: Double?

    public init(url: URL, alt: String? = nil, attachment: JiraAttachmentMeta? = nil, naturalWidth: Double? = nil) {
        self.url = url
        self.alt = alt
        self.attachment = attachment
        self.naturalWidth = naturalWidth
    }
}

public extension AttributedString {
    static let empty = AttributedString("")
}
