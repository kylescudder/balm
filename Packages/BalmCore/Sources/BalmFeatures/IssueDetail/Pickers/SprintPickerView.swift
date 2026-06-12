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

    var body: some View {
        PickerScaffold(title: "Sprint") {
            List {
                Section {
                    Button {
                        onSelect(nil); dismiss()
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                }
                Section("Sprints") {
                    if isLoading && sprints.isEmpty {
                        HStack { ProgressView(); Text("Loading…") }
                    } else {
                        ForEach(sprints) { sprint in
                            Button {
                                onSelect(sprint); dismiss()
                            } label: {
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
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
            let resp = try await env.api.send(
                ProjectEndpoints.Sprints(boardID: board.id, states: ["active", "future"])
            )
            sprints = resp.values
        } catch {
            env.toaster.error("Couldn't load sprints: \(error.localizedDescription)")
        }
    }
}
