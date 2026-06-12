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

    public init(
        id: String,
        filename: String,
        size: Int,
        mimeType: String? = nil,
        isImage: Bool,
        content: URL? = nil,
        thumbnail: URL? = nil,
        created: Date? = nil
    ) {
        self.id = id
        self.filename = filename
        self.size = size
        self.mimeType = mimeType
        self.isImage = isImage
        self.content = content
        self.thumbnail = thumbnail
        self.created = created
    }
}
