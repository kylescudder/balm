import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct VersionsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let current: [JiraVersion]
    let onApply: ([JiraVersion]) -> Void

    @State private var available: [JiraVersion] = []
    @State private var draftIDs: Set<String>
    @State private var isLoading = false
    @State private var searchText = ""

    init(projectKey: String, current: [JiraVersion], onApply: @escaping ([JiraVersion]) -> Void) {
        self.projectKey = projectKey
        self.current = current
        self.onApply = onApply
        self._draftIDs = State(initialValue: Set(current.map(\.id)))
    }

    var body: some View {
        PickerScaffold(
            title: "Fix Versions",
            confirmTitle: "Apply",
            onConfirm: { onApply(available.filter { draftIDs.contains($0.id) }) }
        ) {
            List {
                if isLoading {
                    ProgressView()
                } else if filteredVersions.isEmpty {
                    ContentUnavailableView("No fix versions", systemImage: "tag")
                } else {
                    ForEach(filteredVersions, id: \.id) { version in
                        Button { toggle(version.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(version.name)
                                    if version.released || version.archived {
                                        Text(versionState(version))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if draftIDs.contains(version.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.palette.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search versions")
            .task { await load() }
        }
    }

    private var filteredVersions: [JiraVersion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        return available.filter { $0.name.localizedStandardContains(query) }
    }

    private func versionState(_ version: JiraVersion) -> String {
        [version.released ? "Released" : nil, version.archived ? "Archived" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func toggle(_ id: String) {
        if draftIDs.contains(id) { draftIDs.remove(id) } else { draftIDs.insert(id) }
    }

    private func load() async {
        guard available.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            available = try await env.api.send(ProjectEndpoints.Versions(projectKeyOrId: projectKey))
        } catch {
            env.toaster.error("Couldn't load versions: \(error.localizedDescription)")
        }
    }
}
