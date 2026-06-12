import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct ComponentsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let current: [String]
    let onApply: ([String]) -> Void

    @State private var available: [JiraComponent] = []
    @State private var draft: Set<String>
    @State private var isLoading = false

    init(projectKey: String, current: [String], onApply: @escaping ([String]) -> Void) {
        self.projectKey = projectKey
        self.current = current
        self.onApply = onApply
        self._draft = State(initialValue: Set(current))
    }

    var body: some View {
        PickerScaffold(
            title: "Components",
            confirmTitle: "Apply",
            onConfirm: { onApply(Array(draft).sorted()) }
        ) {
            List {
                if isLoading && available.isEmpty {
                    HStack { ProgressView(); Text("Loading…") }
                } else if available.isEmpty {
                    Text("No components defined for this project.")
                        .foregroundStyle(theme.palette.mutedForeground)
                } else {
                    ForEach(available) { component in
                        toggleRow(name: component.name)
                    }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func toggleRow(name: String) -> some View {
        Toggle(isOn: Binding(
            get: { draft.contains(name) },
            set: { on in
                if on { draft.insert(name) } else { draft.remove(name) }
            }
        )) {
            Text(name).foregroundStyle(theme.palette.foreground)
        }
    }

    private func load() async {
        guard available.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            available = try await env.api.send(ProjectEndpoints.Components(projectKeyOrId: projectKey))
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        } catch {
            env.toaster.error("Couldn't load components: \(error.localizedDescription)")
        }
    }
}
