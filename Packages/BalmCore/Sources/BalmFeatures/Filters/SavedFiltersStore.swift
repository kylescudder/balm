import Foundation
import Observation
import BalmModels

/// Per-project library of named filters. Persists to UserDefaults under
/// `savedFilters.<projectKey>`, mirroring `FilterStore`.
@MainActor
@Observable
public final class SavedFiltersStore {
    public let projectKey: String
    public private(set) var savedFilters: [SavedFilter]

    public init(projectKey: String) {
        self.projectKey = projectKey
        self.savedFilters = Self.load(projectKey: projectKey)
    }

    /// Save the given definition under `name`. A blank name is ignored. If a
    /// filter with the same (case-insensitive) name exists, it is overwritten.
    public func save(name: String, definition: FilterDefinition) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = savedFilters.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedFilters[index].definition = definition
        } else {
            savedFilters.append(SavedFilter(name: trimmed, definition: definition))
        }
        sortAndPersist()
    }

    public func rename(_ filter: SavedFilter, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = savedFilters.firstIndex(where: { $0.id == filter.id }) else { return }
        savedFilters[index].name = trimmed
        sortAndPersist()
    }

    public func delete(_ filter: SavedFilter) {
        savedFilters.removeAll { $0.id == filter.id }
        sortAndPersist()
    }

    // MARK: - Persistence

    private func sortAndPersist() {
        savedFilters.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let data = try? JSONEncoder().encode(savedFilters) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(projectKey))
    }

    static func key(_ projectKey: String) -> String { "savedFilters.\(projectKey)" }

    static func load(projectKey: String) -> [SavedFilter] {
        guard let data = UserDefaults.standard.data(forKey: key(projectKey)),
              let decoded = try? JSONDecoder().decode([SavedFilter].self, from: data)
        else { return [] }
        return decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
