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
    @State private var searchText = ""

    var body: some View {
        PickerScaffold(title: "Sprint") {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label("Backlog", systemImage: "tray.full")
                        Spacer()
                        if currentSprintID == nil { Image(systemName: "checkmark") }
                    }
                }

                if isLoading {
                    ProgressView()
                } else if filteredSprints.isEmpty {
                    ContentUnavailableView("No sprints", systemImage: "calendar")
                } else {
                    ForEach(filteredSprints, id: \.id) { sprint in
                        Button {
                            onSelect(sprint)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(sprint.name)
                                    if !sprint.state.isEmpty {
                                        Text(sprint.state.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if sprint.id == currentSprintID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.palette.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sprints")
            .task { await load() }
        }
    }

    private var filteredSprints: [JiraSprint] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sprints }
        return sprints.filter {
            $0.name.localizedStandardContains(query) || $0.state.localizedStandardContains(query)
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
