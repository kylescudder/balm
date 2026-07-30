import Foundation

public struct JiraComponent: Codable, Sendable, Hashable, Identifiable {
    public var id: String?
    public var name: String

    public init(id: String? = nil, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, value
    }

    /// Decodes both the standard component shape (`name`) and the custom
    /// select-field option shape (`value`) used by tenant "Component" fields
    /// like `customfield_10312`, where the display text lives under `value`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        if let name = try container.decodeIfPresent(String.self, forKey: .name) {
            self.name = name
        } else {
            self.name = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}
