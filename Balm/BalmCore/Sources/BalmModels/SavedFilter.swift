import Foundation

/// A named, reusable filter. Stored per-project and applied from the filter
/// sheet's "Saved Filters" list.
public struct SavedFilter: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var definition: FilterDefinition

    public init(id: UUID = UUID(), name: String, definition: FilterDefinition) {
        self.id = id
        self.name = name
        self.definition = definition
    }
}
