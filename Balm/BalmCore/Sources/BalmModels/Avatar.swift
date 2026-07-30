import Foundation

public struct AvatarURLs: Codable, Sendable, Hashable {
    public var size24: URL?
    public var size32: URL?
    public var size48: URL?

    public init(size24: URL? = nil, size32: URL? = nil, size48: URL? = nil) {
        self.size24 = size24
        self.size32 = size32
        self.size48 = size48
    }

    public var bestAvailable: URL? { size48 ?? size32 ?? size24 }

    enum CodingKeys: String, CodingKey {
        case size24 = "24x24"
        case size32 = "32x32"
        case size48 = "48x48"
    }
}
