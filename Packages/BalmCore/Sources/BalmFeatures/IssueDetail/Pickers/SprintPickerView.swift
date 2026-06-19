import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct SprintPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let currentSprintID: String?
    let onSelect: (JiraSprint?) -> Void

    @State private var sprints: [JiraSprint] = []
    @State private var isLoading = false

    /// Folds the synthetic "Backlog" choice into the same keyboard-navigable
    /// list as the real sprints.
    private enum Entry: Hashable {
        case backlog
        case sprint(JiraSprint)
    }

    private var entries: [Entry] {
        [.backlog] + sprints.map(Entry.sprint)
    }

    private var currentEntry: Entry {
        guard let id = currentSprintID,
              let match = sprints.first(where: { $0.id == id }) else { return .backlog }
        return .sprint(match)
    }

    var body: some View {
        PickerScaffold(title: "Sprint") {
            KeyboardFilterList(
                items: entries,
                prompt: "Filter sprints",
                isLoading: isLoading,
                initialSelection: currentEntry,
                filterText: filterText,
                onActivate: activate
            ) { entry in
                row(entry)
            }
            .task { await load() }
        }
    }

    private func filterText(_ entry: Entry) -> String {
        switch entry {
        case .backlog: return "Backlog"
        case .sprint(let sprint): return "\(sprint.name) \(sprint.state)"
        }
    }

    private func activate(_ entry: Entry) {
        switch entry {
        case .backlog: onSelect(nil)
        case .sprint(let sprint): onSelect(sprint)
        }
        dismiss()
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry {
        case .backlog:
            HStack {
                Image(systemName: "tray.full")
                    .foregroundStyle(theme.palette.mutedForeground)
                    .frame(width: 28)
                Text("Backlog").foregroundStyle(theme.palette.foreground)
                Spacer()
                if currentSprintID == nil {
                    Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                }
            }
            .contentShape(Rectangle())
        case .sprint(let sprint):
            HStack {
                VStack(alignment: .leading) {
                    Text(sprint.name).foregroundStyle(theme.palette.foreground)
                    if !sprint.state.isEmpty {
                        Text(sprint.state.capitalized)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.mutedForeground)
                    }
                }
                Spacer()
                if sprint.id == currentSprintID {
                    Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func load() async {
        guard sprints.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let boards = try await env.api.send(ProjectEndpoints.Boards(projectKeyOrId: projectKey))
            guard let board = boards.values.first else {
                sprints = []
                return
            }
            let resp = try await env.api.send(
                ProjectEndpoints.Sprints(boardID: board.id, states: ["active", "future"])
            )
            sprints = resp.values
        } catch {
            env.toaster.error("Couldn't load sprints: \(error.localizedDescription)")
        }
    }
}
