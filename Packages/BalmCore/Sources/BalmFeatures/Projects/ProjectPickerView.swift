import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

public struct ProjectPickerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme

    @Binding private var selection: JiraProject?
    @State private var projects: [JiraProject] = []
    @State private var isLoading = false
    @State private var error: String?

    public init(selection: Binding<JiraProject?>) {
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            if isLoading && projects.isEmpty {
                HStack { ProgressView(); Text("Loading projects…") }
            } else if let error {
                Text(error).foregroundStyle(theme.palette.destructive)
            } else if projects.isEmpty {
                Text("No projects").foregroundStyle(theme.palette.mutedForeground)
            } else {
                ForEach(projects, id: \.self) { project in
                    NavigationLink(value: project) {
                        VStack(alignment: .leading) {
                            Text(project.name).foregroundStyle(theme.palette.foreground)
                            Text(project.key)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.palette.mutedForeground)
                        }
                    }
                    .tag(project)
                }
            }
        }
        .task { await load() }
        .refreshable { await load(force: true) }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
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
