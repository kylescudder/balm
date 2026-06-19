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
            KeyboardFilterList(
                items: available,
                prompt: "Filter versions",
                isLoading: isLoading,
                emptyText: "No releases defined for this project.",
                filterText: { $0.name },
                onActivate: { toggle($0.id) }
            ) { version in
                HStack {
                    Text(version.name).foregroundStyle(theme.palette.foreground)
                    Spacer()
                    if version.released {
                        BalmChip("Released", tint: theme.palette.color(for: .chart5))
                    }
                    if version.archived {
                        BalmChip("Archived", tint: theme.palette.mutedForeground)
                    }
                    if draftIDs.contains(version.id) {
                        Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                    }
                }
                .contentShape(Rectangle())
            }
            .task { await load() }
        }
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
