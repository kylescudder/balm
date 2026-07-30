import Foundation

public struct JiraBoard: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var type: String?

    public init(id: Int, name: String, type: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
    }
}
