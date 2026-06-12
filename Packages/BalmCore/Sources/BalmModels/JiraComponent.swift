import Foundation

public struct JiraComponent: Codable, Sendable, Hashable, Identifiable {
    public var id: String?
    public var name: String

    public init(id: String? = nil, name: String) {
        self.id = id
        self.name = name
    }
}
