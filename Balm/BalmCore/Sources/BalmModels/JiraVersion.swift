import Foundation

public struct JiraVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var released: Bool
    public var archived: Bool

    public init(id: String, name: String, released: Bool, archived: Bool = false) {
        self.id = id
        self.name = name
        self.released = released
        self.archived = archived
    }
}

public extension JiraVersion {
    static let noReleaseSentinel = "NO_RELEASE"
}
