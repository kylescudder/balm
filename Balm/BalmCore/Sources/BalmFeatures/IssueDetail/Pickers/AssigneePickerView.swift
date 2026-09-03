import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// Type to filter, arrows to move, Return to assign, Esc to cancel. The search
/// field has focus the moment the sheet appears.
struct AssigneePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let currentDisplayName: String?
    let onSelect: (JiraUser?) -> Void

    @State private var users: [JiraUser] = []
    @State private var isLoading = false

    enum Choice: Hashable {
        case unassigned
        case user(JiraUser)
    }

    private var choices: [Choice] {
        [.unassigned] + users.map(Choice.user)
    }

    private var current: Choice {
        guard let name = currentDisplayName,
              let user = users.first(where: { $0.displayName == name })
        else { return .unassigned }
        return .user(user)
    }

    var body: some View {
        PickerScaffold(title: "Assignee") {
            KeyboardFilterList(
                items: choices,
                prompt: "Search people",
                isLoading: isLoading,
                emptyText: "No one matches.",
                initialSelection: current,
                filterText: { choice in
                    switch choice {
                    case .unassigned: return "Unassigned"
                    case .user(let user): return "\(user.displayName) \(user.emailAddress ?? "")"
                    }
                },
                onActivate: { choice in
                    switch choice {
                    case .unassigned: onSelect(nil)
                    case .user(let user): onSelect(user)
                    }
                    dismiss()
                }
            ) { choice in
                row(choice)
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func row(_ choice: Choice) -> some View {
        HStack(spacing: 10) {
            switch choice {
            case .unassigned:
                Image(systemName: "person.crop.circle.dashed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                Text("Unassigned")
            case .user(let user):
                AvatarView(name: user.displayName, avatarURL: user.avatarUrls?.bestAvailable, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName)
                    if let email = user.emailAddress {
                        Text(email)
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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard users.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await env.api.send(UserEndpoints.ProjectUsers(projectKey: projectKey))
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        } catch {
            env.toaster.report(error, "Couldn't load users")
        }
    }
}
