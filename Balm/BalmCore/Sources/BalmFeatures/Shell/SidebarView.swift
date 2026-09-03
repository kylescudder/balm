import SwiftUI
import BalmModels
import BalmDesignSystem

/// A place in the app. The sidebar on the Mac and the tab sidebar on iPad both
/// list these; selecting one either switches the content column or applies a
/// filter to the active project.
enum SidebarItem: Hashable {
    case inbox
    case myIssues
    case project(String)
    case view(UUID)
}

/// The Mac sidebar: Inbox and My issues on top, then the projects the account
/// can see, then the active project's saved filters as views. The account row
/// at the bottom opens Settings.
struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var selection: SidebarItem?
    let savedFilters: [SavedFilter]

    // Collapsible, remembered across launches. Native sidebar sections show
    // the hide/show control on hover.
    @AppStorage("sidebar.projectsExpanded") private var projectsExpanded = true
    @AppStorage("sidebar.viewsExpanded") private var viewsExpanded = true

    var body: some View {
        List(selection: $selection) {
            Label("Inbox", systemImage: env.inboxStore.unreadCount > 0 ? "tray.full" : "tray")
                .badge(env.inboxStore.unreadCount)
                .tag(SidebarItem.inbox)
            Label("My issues", systemImage: "person")
                .tag(SidebarItem.myIssues)

            Section(isExpanded: $projectsExpanded) {
                ForEach(env.projectListStore.projects) { project in
                    Label {
                        Text(project.name)
                    } icon: {
                        ProjectAvatar(
                            project: project,
                            size: 18,
                            isActive: project.id == env.activeProjectStore.project?.id
                        )
                    }
                    .tag(SidebarItem.project(project.id))
                }
                if env.projectListStore.projects.isEmpty && env.projectListStore.isLoading {
                    ProgressView().controlSize(.small)
                }
            } header: {
                Text("Projects")
            }

            Section(isExpanded: $viewsExpanded) {
                if savedFilters.isEmpty {
                    Text("Save a filter to add a view here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(savedFilters) { filter in
                    Label(filter.name, systemImage: "line.3.horizontal.decrease")
                        .tag(SidebarItem.view(filter.id))
                }
            } header: {
                Text("Views")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { accountRow }
        .task { await env.projectListStore.loadIfNeeded() }
    }

    private var accountRow: some View {
        HStack(spacing: 8) {
            AvatarView(name: userName, avatarURL: userAvatar, size: 22)
            Text(userName ?? "Signed in")
                .lineLimit(1)
            Spacer(minLength: 0)
            #if os(macOS)
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var userName: String? {
        if case .signedIn(_, _, let user) = env.authState { return user?.displayName }
        return nil
    }

    private var userAvatar: URL? {
        if case .signedIn(_, _, let user) = env.authState { return user?.avatarUrls?.bestAvailable }
        return nil
    }
}
