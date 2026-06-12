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
    @State private var query = ""

    var body: some View {
        PickerScaffold(title: "Assignee") {
            List {
                Section {
                    row(name: "Unassigned", icon: "person.slash") {
                        onSelect(nil); dismiss()
                    }
                }
                Section("People") {
                    if isLoading && users.isEmpty {
                        HStack { ProgressView(); Text("Loading…") }
                    } else {
                        ForEach(filtered) { user in
                            Button {
                                onSelect(user); dismiss()
                            } label: {
                                HStack(spacing: theme.spacing.s) {
                                    AvatarView(name: user.displayName, avatarURL: user.avatarUrls?.bestAvailable, size: 28)
                                    VStack(alignment: .leading) {
                                        Text(user.displayName)
                                            .foregroundStyle(theme.palette.foreground)
                                        if let email = user.emailAddress {
                                            Text(email)
                                                .font(theme.typography.caption)
                                                .foregroundStyle(theme.palette.mutedForeground)
                                        }
                                    }
                                    Spacer()
                                    if user.accountId == currentAccountID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(theme.palette.primary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search people")
            .task { await load() }
        }
    }

    private var filtered: [JiraUser] {
        guard !query.isEmpty else { return users }
        let q = query.lowercased()
        return users.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.emailAddress?.lowercased().contains(q) ?? false)
        }
    }

    private func row(name: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundStyle(theme.palette.mutedForeground)
                Text(name).foregroundStyle(theme.palette.foreground)
                Spacer()
                if currentAccountID == nil {
                    Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                }
            }
        }
        .buttonStyle(.plain)
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
