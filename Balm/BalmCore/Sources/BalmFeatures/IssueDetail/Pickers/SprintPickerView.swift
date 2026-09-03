import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct SprintPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let currentSprintID: String?
    let onSelect: (JiraSprint?) -> Void

    @State private var sprints: [JiraSprint] = []
    @State private var isLoading = false

    enum Choice: Hashable {
        case backlog
        case sprint(JiraSprint)
    }

    private var choices: [Choice] {
        [.backlog] + sprints.map(Choice.sprint)
    }

    private var current: Choice {
        guard let id = currentSprintID, let sprint = sprints.first(where: { $0.id == id }) else { return .backlog }
        return .sprint(sprint)
    }

    var body: some View {
        PickerScaffold(title: "Sprint") {
            KeyboardFilterList(
                items: choices,
                prompt: "Filter sprints",
                isLoading: isLoading,
                emptyText: "No sprints match.",
                initialSelection: current,
                filterText: { choice in
                    switch choice {
                    case .backlog: return "Backlog"
                    case .sprint(let sprint): return "\(sprint.name) \(sprint.state)"
                    }
                },
                onActivate: { choice in
                    switch choice {
                    case .backlog: onSelect(nil)
                    case .sprint(let sprint): onSelect(sprint)
                    }
                    dismiss()
                }
            ) { choice in
                HStack(spacing: 10) {
                    switch choice {
                    case .backlog:
                        Label("Backlog", systemImage: "tray")
                    case .sprint(let sprint):
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sprint.name)
                            if !sprint.state.isEmpty {
                                Text(sprint.state.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if choice == current {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .task { await load() }
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
            sprints = try await env.api.allSprints(boardID: board.id, states: ["active", "future"])
        } catch {
            env.toaster.report(error, "Couldn't load sprints")
        }
    }
}
