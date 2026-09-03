import Foundation
import Observation
import BalmModels
import BalmAPI

/// The projects the signed-in user can see, loaded once per session and shared
/// by the sidebar, the iPad tab sidebar, the iPhone title menu and the project
/// chooser. Also the handful Jira says they opened most recently, which the
/// welcome screen puts first. Reset on sign-out so a different account never
/// inherits the list.
@MainActor
@Observable
public final class ProjectListStore {
    public private(set) var projects: [JiraProject] = []
    /// Most recently viewed first. Empty when Jira has no history or the
    /// request fails; never an error state of its own.
    public private(set) var recent: [JiraProject] = []
    public private(set) var isLoading = false
    public private(set) var error: String?

    private let api: JiraClient
    private var loaded = false

    public init(api: JiraClient) {
        self.api = api
    }

    public func loadIfNeeded() async {
        guard !loaded, !isLoading else { return }
        await load()
    }

    public func reload() async {
        await load()
    }

    public func reset() {
        projects = []
        recent = []
        loaded = false
        error = nil
    }

    public func project(id: String) -> JiraProject? {
        projects.first { $0.id == id }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let listRequest = api.send(ProjectEndpoints.List())
        async let recentRequest = api.send(ProjectEndpoints.Recent())
        do {
            let response = try await listRequest
            projects = response.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            error = nil
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
        if let recentProjects = try? await recentRequest {
            // Keep only projects that are still visible in the full list, so a
            // recently viewed but since-archived project cannot be chosen.
            let visible = Set(projects.map(\.id))
            recent = recentProjects.filter { visible.isEmpty || visible.contains($0.id) }.prefix(6).map { $0 }
        }
    }
}
