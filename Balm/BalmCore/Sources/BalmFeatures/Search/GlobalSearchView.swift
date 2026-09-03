#if !os(macOS)
import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// The iOS Search tab: an instance-wide issue search. Typing a key and pressing
/// return opens that issue directly; anything else searches every project.
struct GlobalSearchView: View {
    @Environment(AppEnvironment.self) private var env
    let project: JiraProject

    @State private var model: IssueListViewModel
    @State private var query = ""
    @State private var path: [JiraIssue] = []

    init(project: JiraProject) {
        self.project = project
        self._model = State(initialValue: IssueListViewModel(project: project, api: BalmAPI_PlaceholderForState.shared.api))
    }

    var body: some View {
        Group {
            switch model.searchState {
            case .idle:
                ContentUnavailableView {
                    Label("Search issues", systemImage: "magnifyingglass")
                } description: {
                    Text("Search titles, descriptions and comments across every project. Type a key like \(project.key)-12 to open it directly.")
                }
            case .searching:
                ProgressView("Searching all projects")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't search", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            case .loaded:
                if model.globalResults.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(model.globalResults, id: \.self) { issue in
                        NavigationLink(value: issue) {
                            IssueRowView(issue: issue)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("Search")
        .navigationDestination(for: JiraIssue.self) { issue in
            IssueDetailView(issue: issue)
        }
        .searchable(text: $query, prompt: "Search issues")
        .onSubmit(of: .search) {
            Task { await submit() }
        }
        .onChange(of: query) { _, next in
            model.invalidateSearchIfQueryChanged(next)
        }
        .task {
            model = IssueListViewModel(project: project, api: env.api, toaster: env.toaster)
        }
    }

    private func submit() async {
        let raw = query.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        if let key = IssueKey.normalise(raw, projectKey: project.key),
           let issue = await model.fetchIssue(key: key, notifyFailure: false) {
            path.append(issue)
            return
        }
        await model.search(raw)
    }
}
#endif
