import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// First-run project picker (and "Change Project…" surface). Native search bar
/// plus a tappable list: choosing a project selects it and proceeds in one tap,
/// so there's no Continue button to fight the system search's nav-bar takeover.
public struct ProjectChooserView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let isFirstRun: Bool

    @State private var projects: [JiraProject] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var query = ""

    public init(isFirstRun: Bool = false) {
        self.isFirstRun = isFirstRun
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(isFirstRun ? "Welcome to Balm" : "Change Project")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                #if os(macOS)
                .searchable(text: $query, prompt: "Filter projects")
                #else
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter projects")
                #endif
                .task { await load() }
        }
        // Cap and centre the width so first-run (shown as the full-window root
        // on macOS) doesn't stretch rows across the whole display.
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 600, maxWidth: 680, minHeight: 560, maxHeight: .infinity)
        #endif
    }

    /// Tapping a project is the action: store it and proceed. On first run,
    /// setting the active project swaps the root away from this chooser.
    private func select(_ project: JiraProject) {
        env.activeProjectStore.set(project)
        Haptics.fire(.success)
        if !isFirstRun { dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && projects.isEmpty {
            ProgressView("Loading projects…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView {
                Label("Couldn't load projects", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await load(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(filtered) { project in
                    Button { select(project) } label: {
                        ProjectRow(
                            project: project,
                            isCurrent: project.id == env.activeProjectStore.project?.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if isFirstRun {
                    heroHeader
                        .padding(.bottom, theme.spacing.m)
                        .background(.bar)
                }
            }
        }
    }

    private var heroHeader: some View {
        VStack(spacing: theme.spacing.s) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 36))
                .foregroundStyle(theme.palette.primary)
                .padding(.top, theme.spacing.m)
            Text("Pick your project")
                .font(theme.typography.title2)
                .foregroundStyle(theme.palette.foreground)
            Text("Choose the project you work in most. You can change this any time from Settings.")
                .font(theme.typography.callout)
                .foregroundStyle(theme.palette.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, theme.spacing.xl)
                .padding(.bottom, theme.spacing.s)
        }
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isFirstRun {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var filtered: [JiraProject] {
        guard !query.isEmpty else { return projects }
        let q = query.lowercased()
        return projects.filter {
            $0.name.lowercased().contains(q) || $0.key.lowercased().contains(q)
        }
    }

    private func load(force: Bool = false) async {
        if !force && !projects.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await env.api.send(ProjectEndpoints.List())
            projects = response.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ProjectRow: View {
    @Environment(\.balmTheme) private var theme
    let project: JiraProject
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radii.sm)
                    .fill(theme.palette.secondary)
                    .frame(width: 32, height: 32)
                Text(String(project.key.prefix(2)))
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.palette.foreground)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.foreground)
                Text(project.key)
                    .font(theme.typography.caption.monospaced())
                    .foregroundStyle(theme.palette.mutedForeground)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.palette.primary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.palette.mutedForeground)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
