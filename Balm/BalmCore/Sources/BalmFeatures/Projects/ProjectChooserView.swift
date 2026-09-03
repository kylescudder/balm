import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// Two jobs, one view. On first run it is the welcome screen: who you are
/// signed in as, the projects you opened most recently as tiles, and every
/// project you can see in a grid with its own avatar. As the "Change project"
/// sheet it is the same grid without the welcome. Choosing a project selects it
/// and proceeds in one click.
public struct ProjectChooserView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let isFirstRun: Bool

    @State private var query = ""

    public init(isFirstRun: Bool = false) {
        self.isFirstRun = isFirstRun
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(isFirstRun ? "Welcome to Balm" : "Change project")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                #if os(macOS)
                .searchable(text: $query, prompt: "Filter projects")
                #else
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter projects")
                #endif
                .task { await env.projectListStore.loadIfNeeded() }
        }
        .modifier(SheetSizing(isSheet: !isFirstRun))
    }

    private func select(_ project: JiraProject) {
        env.activeProjectStore.set(project)
        Haptics.fire(.success)
        if !isFirstRun { dismiss() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let store = env.projectListStore
        if store.isLoading && store.projects.isEmpty {
            ProgressView("Loading your projects")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.error, store.projects.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load projects", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await store.reload() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if isFirstRun {
            welcome
        } else {
            changeProjectList
        }
    }

    /// The welcome layout: identity, the question, recent tiles, the full grid.
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                identity
                VStack(alignment: .leading, spacing: 6) {
                    Text("Which project do you work in most?")
                        .font(theme.typography.issueTitle)
                    Text("It opens first every time you launch Balm. Every other project stays one click away in the sidebar.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                if isSearching == false, !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Recent", count: nil)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 12)],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(recentProjects) { project in
                                ProjectTile(project: project) { select(project) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(isSearching ? "Matches" : "All projects", count: filtered.count)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                        alignment: .leading,
                        spacing: 2
                    ) {
                        ForEach(filtered) { project in
                            ProjectGridRow(project: project) { select(project) }
                        }
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }

    /// The mark, the site, and who is signed in.
    private var identity: some View {
        HStack(spacing: 16) {
            Image("BalmMark")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(siteName ?? "Balm")
                    .font(.title2.weight(.semibold))
                Text(userName.map { "Signed in as \($0)" } ?? "Signed in")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
            if let count {
                Text(count, format: .number)
                    .font(.headline.weight(.regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// The compact sheet used to switch project once inside the app.
    private var changeProjectList: some View {
        List {
            if !isSearching, !recentProjects.isEmpty {
                Section("Recent") {
                    ForEach(recentProjects) { project in
                        listRow(project)
                    }
                }
            }
            Section(isSearching ? "Matches" : "All projects") {
                ForEach(filtered) { project in
                    listRow(project)
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .refreshable { await env.projectListStore.reload() }
    }

    private func listRow(_ project: JiraProject) -> some View {
        Button { select(project) } label: {
            HStack(spacing: 12) {
                ProjectAvatar(project: project, size: 28, isActive: isCurrent(project))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                    Text(project.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if isCurrent(project) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isFirstRun {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Data

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var recentProjects: [JiraProject] {
        env.projectListStore.recent
    }

    private var filtered: [JiraProject] {
        let projects = env.projectListStore.projects
        guard isSearching else { return projects }
        let q = query.lowercased()
        return projects.filter {
            $0.name.lowercased().contains(q) || $0.key.lowercased().contains(q)
        }
    }

    private func isCurrent(_ project: JiraProject) -> Bool {
        project.id == env.activeProjectStore.project?.id
    }

    private var siteName: String? {
        if case .signedIn(let siteName, _, _) = env.authState { return siteName }
        return nil
    }

    private var userName: String? {
        if case .signedIn(_, _, let user) = env.authState { return user?.displayName }
        return nil
    }
}

/// A recently opened project as a tile: avatar, name, key, on a material card.
private struct ProjectTile: View {
    let project: JiraProject
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ProjectAvatar(project: project, size: 36)
                Spacer(minLength: 0)
                Text(project.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(project.key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: isHovered ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("\(project.name), \(project.key)")
    }
}

/// One project in the full grid: avatar, name, key. Highlights on hover.
private struct ProjectGridRow: View {
    let project: JiraProject
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProjectAvatar(project: project, size: 22)
                Text(project.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(project.key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(project.name), \(project.key)")
    }
}

/// The sheet gets a fixed footprint on macOS; the first-run window is left to
/// the scene so the grid can use the whole window.
private struct SheetSizing: ViewModifier {
    let isSheet: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        if isSheet {
            content.frame(minWidth: 520, idealWidth: 620, maxWidth: 720, minHeight: 560, maxHeight: .infinity)
        } else {
            content.frame(minWidth: 720, minHeight: 520)
        }
        #else
        content
        #endif
    }
}
