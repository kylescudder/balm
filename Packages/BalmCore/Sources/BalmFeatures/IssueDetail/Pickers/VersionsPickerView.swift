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
            List {
                if isLoading && available.isEmpty {
                    HStack { ProgressView(); Text("Loading…") }
                } else if available.isEmpty {
                    Text("No releases defined for this project.")
                        .foregroundStyle(theme.palette.mutedForeground)
                } else {
                    ForEach(available) { version in
                        Toggle(isOn: Binding(
                            get: { draftIDs.contains(version.id) },
                            set: { on in
                                if on { draftIDs.insert(version.id) }
                                else { draftIDs.remove(version.id) }
                            }
                        )) {
                            HStack {
                                Text(version.name).foregroundStyle(theme.palette.foreground)
                                Spacer()
                                if version.released {
                                    BalmChip("Released", tint: theme.palette.color(for: .chart5))
                                }
                                if version.archived {
                                    BalmChip("Archived", tint: theme.palette.mutedForeground)
                                }
                            }
                        }
                    }
                }
            }
            .task { await load() }
        }
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
