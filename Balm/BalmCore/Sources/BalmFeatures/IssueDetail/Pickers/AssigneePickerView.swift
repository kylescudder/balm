import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct AssigneePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let currentAccountID: String?
    let onSelect: (JiraUser?) -> Void

    @State private var users: [JiraUser] = []
    @State private var isLoading = false
    @State private var searchText = ""

    var body: some View {
        PickerScaffold(title: "Assignee") {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Label("Unassigned", systemImage: "person.slash")
                        Spacer()
                        if currentAccountID == nil { Image(systemName: "checkmark") }
                    }
                }

                if isLoading {
                    ProgressView()
                } else if filteredUsers.isEmpty {
                    ContentUnavailableView("No people", systemImage: "person.2")
                } else {
                    ForEach(filteredUsers, id: \.accountId) { user in
                        Button {
                            onSelect(user)
                            dismiss()
                        } label: {
                            HStack(spacing: theme.spacing.s) {
                                AvatarView(name: user.displayName, avatarURL: user.avatarUrls?.bestAvailable, size: 28)
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                    if let email = user.emailAddress {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if user.accountId == currentAccountID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.palette.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search people")
            .task { await load() }
        }
    }

    private var filteredUsers: [JiraUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return users }
        return users.filter {
            $0.displayName.localizedStandardContains(query)
                || ($0.emailAddress?.localizedStandardContains(query) ?? false)
        }
    }

    private func load() async {
        guard users.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await env.api.send(UserEndpoints.ProjectUsers(projectKey: projectKey))
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        } catch {
            env.toaster.error("Couldn't load users: \(error.localizedDescription)")
        }
    }
}
