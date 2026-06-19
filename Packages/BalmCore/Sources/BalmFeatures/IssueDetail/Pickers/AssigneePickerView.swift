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

    /// Folds the synthetic "Unassigned" choice into the same keyboard-navigable
    /// list as the real users.
    private enum Entry: Hashable {
        case unassigned
        case user(JiraUser)
    }

    private var entries: [Entry] {
        [.unassigned] + users.map(Entry.user)
    }

    private var currentEntry: Entry {
        guard let id = currentAccountID,
              let match = users.first(where: { $0.accountId == id }) else { return .unassigned }
        return .user(match)
    }

    var body: some View {
        PickerScaffold(title: "Assignee") {
            KeyboardFilterList(
                items: entries,
                prompt: "Filter people",
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
        case .unassigned: return "Unassigned"
        case .user(let user): return "\(user.displayName) \(user.emailAddress ?? "")"
        }
    }

    private func activate(_ entry: Entry) {
        switch entry {
        case .unassigned: onSelect(nil)
        case .user(let user): onSelect(user)
        }
        dismiss()
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry {
        case .unassigned:
            HStack {
                Image(systemName: "person.slash")
                    .frame(width: 28)
                    .foregroundStyle(theme.palette.mutedForeground)
                Text("Unassigned").foregroundStyle(theme.palette.foreground)
                Spacer()
                if currentAccountID == nil {
                    Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                }
            }
            .contentShape(Rectangle())
        case .user(let user):
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
            .contentShape(Rectangle())
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
