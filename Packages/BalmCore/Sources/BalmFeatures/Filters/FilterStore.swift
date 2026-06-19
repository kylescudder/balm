import Foundation
import Observation
import BalmModels

@MainActor
@Observable
public final class FilterStore {
    public let projectKey: String
    public var definition: FilterDefinition {
        didSet { persistDefinition() }
    }

    public init(projectKey: String) {
        self.projectKey = projectKey
        self.definition = Self.loadDefinition(projectKey: projectKey)
    }

    public func clear() {
        definition = .empty
    }

    // MARK: - Persistence

    private func persistDefinition() {
        guard let data = try? JSONEncoder().encode(definition) else { return }
        UserDefaults.standard.set(data, forKey: Self.definitionKey(projectKey))
    }

    static func definitionKey(_ projectKey: String) -> String { "filterDefinition.\(projectKey)" }
    static func legacyKey(_ projectKey: String) -> String { "filters.\(projectKey)" }

    /// Load the stored `FilterDefinition`. Falls back to a one-time migration of
    /// the legacy flat `FilterOptions` (key `filters.<projectKey>`) so existing
    /// users keep their active filter; otherwise `.empty`.
    static func loadDefinition(projectKey: String) -> FilterDefinition {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: definitionKey(projectKey)),
           let decoded = try? JSONDecoder().decode(FilterDefinition.self, from: data) {
            return decoded
        }
        if let legacyData = defaults.data(forKey: legacyKey(projectKey)),
           let legacy = try? JSONDecoder().decode(FilterOptions.self, from: legacyData) {
            return legacy.asFilterDefinition
        }
        return .empty
    }
}
