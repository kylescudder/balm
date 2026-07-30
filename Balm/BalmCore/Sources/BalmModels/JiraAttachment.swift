import Foundation

public struct JiraAttachmentMeta: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var filename: String
    public var size: Int
    public var mimeType: String?
    public var isImage: Bool
    public var content: URL?
    public var thumbnail: URL?
    public var created: Date?
    /// Atlassian Media Services file UUID used by ADF `media` nodes. This is
    /// distinct from Jira's numeric attachment `id`.
    public var mediaFileID: String?

    public init(
        id: String,
        filename: String,
        size: Int,
        mimeType: String? = nil,
        isImage: Bool,
        content: URL? = nil,
        thumbnail: URL? = nil,
        created: Date? = nil,
        mediaFileID: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.size = size
        self.mimeType = mimeType
        self.isImage = isImage
        self.content = content
        self.thumbnail = thumbnail
        self.created = created
        self.mediaFileID = mediaFileID
    }
}
