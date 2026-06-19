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
            KeyboardFilterList(
                items: available,
                prompt: "Filter components",
                isLoading: isLoading,
                emptyText: "No components defined for this project.",
                filterText: { $0.name },
                onActivate: { toggle($0.name) }
            ) { component in
                HStack {
                    Text(component.name).foregroundStyle(theme.palette.foreground)
                    Spacer()
                    if draft.contains(component.name) {
                        Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                    }
                }
                .contentShape(Rectangle())
            }
            .task { await load() }
        }
    }

    private func toggle(_ name: String) {
        if draft.contains(name) { draft.remove(name) } else { draft.insert(name) }
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
