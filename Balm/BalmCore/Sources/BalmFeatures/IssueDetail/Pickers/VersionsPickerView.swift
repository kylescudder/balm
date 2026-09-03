import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// Multi-select: Return toggles the highlighted version and keeps the sheet
/// open; ⌘↩ applies.
struct VersionsPickerView: View {
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let current: [JiraVersion]
    let onApply: ([JiraVersion]) -> Void

    @State private var available: [JiraVersion] = []
    @State private var draftIDs: Set<String>
    @State private var isLoading = false

    init(projectKey: String, current: [JiraVersion], onApply: @escaping ([JiraVersion]) -> Void) {
        self.projectKey = projectKey
        self.current = current
        self.onApply = onApply
        self._draftIDs = State(initialValue: Set(current.map(\.id)))
    }

    var body: some View {
        PickerScaffold(
            title: "Fix versions",
            confirmTitle: "Apply",
            onConfirm: { onApply(available.filter { draftIDs.contains($0.id) }) }
        ) {
            KeyboardFilterList(
                items: available,
                prompt: "Filter versions",
                isLoading: isLoading,
                emptyText: "No versions match.",
                initialSelection: available.first { draftIDs.contains($0.id) },
                filterText: { $0.name },
                onActivate: { toggle($0.id) }
            ) { version in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(version.name)
                        if version.released || version.archived {
                            Text(versionState(version))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: draftIDs.contains(version.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(draftIDs.contains(version.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                }
                .contentShape(Rectangle())
            }
            .task { await load() }
        }
    }

    private func versionState(_ version: JiraVersion) -> String {
        [version.released ? "Released" : nil, version.archived ? "Archived" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
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
            env.toaster.report(error, "Couldn't load versions")
        }
    }
}
