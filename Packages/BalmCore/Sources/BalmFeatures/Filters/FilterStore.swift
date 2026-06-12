import Foundation
import Observation
import BalmModels

@MainActor
@Observable
public final class FilterStore {
    public let projectKey: String
    public var filters: FilterOptions {
        didSet { persistFilters() }
    }

    public init(projectKey: String) {
        self.projectKey = projectKey
        self.filters = Self.loadFilters(projectKey: projectKey)
    }

    public func clear() {
        filters = .empty
    }

    // MARK: - Persistence

    private func persistFilters() {
        guard let data = try? JSONEncoder().encode(filters) else { return }
        UserDefaults.standard.set(data, forKey: Self.filterKey(projectKey))
    }

    static func filterKey(_ projectKey: String) -> String { "filters.\(projectKey)" }

    static func loadFilters(projectKey: String) -> FilterOptions {
        guard let data = UserDefaults.standard.data(forKey: filterKey(projectKey)),
              let decoded = try? JSONDecoder().decode(FilterOptions.self, from: data)
        else { return .empty }
        return decoded
    }
}
