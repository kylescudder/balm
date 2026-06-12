import Foundation
import Observation
import BalmModels
import BalmAPI

@MainActor
@Observable
public final class IssueListViewModel {
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public let project: JiraProject
    public private(set) var issues: [JiraIssue] = []
    public private(set) var availableSprints: [JiraSprint] = []
    public private(set) var selectedSprintIDs: Set<String> = []
    public private(set) var userFilters: FilterOptions = .empty
    public private(set) var loadState: LoadState = .idle

    /// Dropdown pools for the filter sheet. Derived from the issues in the
    /// current sprint context *before* user filters are applied, so the menus
    /// keep offering every value (you can widen a filter without clearing it).
    public private(set) var filterOptions: AvailableFilterOptions = .empty
    /// The sprint set `filterOptions` was last built for — lets us skip the
    /// extra unfiltered fetch when only the user filters changed.
    private var filterOptionsSprints: Set<String>?

    /// Issues grouped into status columns, ordered for the Kanban board.
    /// Columns are bucketed by normalised status name, sorted by
    /// (group rank, statusCategory.key precedence, alphabetical).
    public var columns: [BoardColumn] {
        Self.columns(from: issues)
    }

    static func columns(from issues: [JiraIssue]) -> [BoardColumn] {
        let grouped = Dictionary(grouping: issues) { issue in
            StatusNormaliser.normalise(issue.status.name)
        }
        let categoryPrecedence = ["new": 0, "indeterminate": 1, "done": 2]

        let sortedKeys: [String] = grouped.keys.sorted { lhs, rhs in
            let lr = StatusNormaliser.groupRank(lhs)
            let rr = StatusNormaliser.groupRank(rhs)
            if lr != rr { return lr < rr }

            // Within a group, prefer the statusCategory.key precedence
            // from the first issue in the bucket.
            let lc = grouped[lhs]?.first?.status.statusCategory.key ?? ""
            let rc = grouped[rhs]?.first?.status.statusCategory.key ?? ""
            let lp = categoryPrecedence[lc, default: 9]
            let rp = categoryPrecedence[rc, default: 9]
            if lp != rp { return lp < rp }

            return lhs.localizedCompare(rhs) == .orderedAscending
        }

        return sortedKeys.map { key in
            let bucket = grouped[key] ?? []
            return BoardColumn(
                id: key,
                title: key,
                statusKeys: Array(Set(bucket.map(\.status.name))),
                issues: bucket
            )
        }
    }

    private let api: JiraClient
    private let toaster: Toaster?
    private var loadTask: Task<Void, Never>?

    public init(project: JiraProject, api: JiraClient, toaster: Toaster? = nil) {
        self.project = project
        self.api = api
        self.toaster = toaster
        self.selectedSprintIDs = Self.restoreSprintSelection(projectKey: project.key)
    }

    public func loadSprintsIfNeeded() async {
        guard availableSprints.isEmpty else { return }
        do {
            let boards = try await api.send(ProjectEndpoints.Boards(projectKeyOrId: project.key))
            guard let board = boards.values.first else {
                availableSprints = [JiraSprint.backlog]
                if selectedSprintIDs.isEmpty {
                    selectedSprintIDs = [JiraSprint.backlog.name]
                }
                return
            }
            let sprintsResponse: ProjectEndpoints.Sprints.PagedResponse
            do {
                sprintsResponse = try await api.send(
                    ProjectEndpoints.Sprints(boardID: board.id, states: ["active", "future"])
                )
            } catch {
                // Kanban boards have no sprints (`/sprint` returns 400). That's
                // expected, not an error — fall back to backlog, which lists
                // every issue not in a sprint (i.e. all of them). No toast.
                useBacklogOnly()
                return
            }
            availableSprints = [JiraSprint.backlog] + sprintsResponse.values

            // Default selection: prefer active sprints; fall back to all
            // future sprints; fall back to backlog so the user sees something
            // on first load. Persisted selection (when present) takes precedence.
            if selectedSprintIDs.isEmpty {
                let active = sprintsResponse.values
                    .filter { $0.state.uppercased() == "ACTIVE" }
                    .map(\.name)
                let future = sprintsResponse.values
                    .filter { $0.state.uppercased() == "FUTURE" }
                    .map(\.name)
                if !active.isEmpty {
                    selectedSprintIDs = Set(active)
                } else if !future.isEmpty {
                    selectedSprintIDs = Set(future)
                } else {
                    selectedSprintIDs = [JiraSprint.backlog.name]
                }
            }
        } catch {
            // No board / no permission / network blip — fall back to backlog so
            // the user at least has something, and surface the failure.
            useBacklogOnly()
            toaster?.error("Sprints unavailable: \(error.localizedDescription)")
        }
    }

    private func useBacklogOnly() {
        availableSprints = [JiraSprint.backlog]
        if selectedSprintIDs.isEmpty {
            selectedSprintIDs = [JiraSprint.backlog.name]
        }
    }

    public func setSprintSelection(_ ids: Set<String>) {
        selectedSprintIDs = ids
        Self.persistSprintSelection(ids, projectKey: project.key)
        reload()
    }

    public func setUserFilters(_ filters: FilterOptions) {
        guard userFilters != filters else { return }
        userFilters = filters
        reload()
    }

    public func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    /// Awaitable reload for `.refreshable` — keeps the pull-to-refresh spinner
    /// on screen until the fetch actually resolves.
    public func reloadAwaiting() async {
        loadTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        loadState = .loading
        let names = availableSprints
            .filter { selectedSprintIDs.contains($0.name) || selectedSprintIDs.contains($0.id) }
            .map(\.name)
        guard !names.isEmpty else {
            issues = []
            filterOptions = .empty
            filterOptionsSprints = nil
            loadState = .loaded
            return
        }
        let combined = FilterOptions(
            status: userFilters.status,
            priority: userFilters.priority,
            assignee: userFilters.assignee,
            issueType: userFilters.issueType,
            labels: userFilters.labels,
            components: userFilters.components,
            reporter: userFilters.reporter,
            sprint: names,
            release: userFilters.release,
            dueDateFrom: userFilters.dueDateFrom,
            dueDateTo: userFilters.dueDateTo
        )
        do {
            issues = try await api.issues(projectKey: project.key, filters: combined)
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
            return
        }
        await updateFilterOptions(sprintNames: names)
    }

    /// Rebuild the filter-sheet pools from the unfiltered sprint context. When
    /// no user filters are active the freshly fetched `issues` already *are*
    /// that context, so we derive directly. Otherwise we make one extra fetch
    /// scoped to sprints only — but just once per sprint set, not per filter
    /// change.
    private func updateFilterOptions(sprintNames: [String]) async {
        let key = Set(sprintNames)
        if userFilters.isEmpty {
            filterOptions = AvailableFilterOptions.from(issues)
            filterOptionsSprints = key
            return
        }
        guard filterOptionsSprints != key else { return }
        let sprintOnly = FilterOptions(sprint: sprintNames)
        if let all = try? await api.issues(projectKey: project.key, filters: sprintOnly) {
            filterOptions = AvailableFilterOptions.from(all)
            filterOptionsSprints = key
        }
    }

    /// Fetch a single issue by key for the ⌘K go-to-ticket flow — works even
    /// when the issue isn't in the currently loaded view. Toasts and returns
    /// nil on failure (e.g. unknown key).
    public func fetchIssue(key: String) async -> JiraIssue? {
        do {
            let raw = try await api.send(IssueEndpoints.GetDetail(issueKey: key))
            return IssueDetailMapper.decode(raw).0
        } catch {
            toaster?.error("Couldn't open \(key): \(error.localizedDescription)")
            return nil
        }
    }

    /// Apply an issue change broadcast by the detail screen (status, assignee,
    /// sprint, …) so the matching board/list card updates immediately — columns
    /// recompute off `issues`, so a status change re-buckets the card at once.
    public func applyExternalUpdate(_ issue: JiraIssue) {
        if let index = issues.firstIndex(where: { $0.key == issue.key }) {
            issues[index] = issue
        }
    }

    // MARK: - Drag & drop

    /// Move an issue to the status group represented by `column` (drag-and-drop
    /// on the board) by finding and applying a matching workflow transition.
    /// Optimistic with rollback; toasts when no transition is permitted.
    public func moveIssue(key: String, to column: BoardColumn) async {
        guard let index = issues.firstIndex(where: { $0.key == key }) else { return }
        // No-op if the card is already in the target column.
        if StatusNormaliser.normalise(issues[index].status.name) == column.id { return }

        let snapshot = issues[index]
        do {
            let resp = try await api.send(IssueEndpoints.Transitions(issueKey: key))
            let match = resp.transitions.first {
                column.statusKeys.contains($0.to.name)
                    || StatusNormaliser.normalise($0.to.name) == column.id
            }
            guard let transition = match else {
                toaster?.error("Can't move \(key) to \(column.title) — no available transition.")
                return
            }
            // Optimistically restatus so the card jumps columns immediately.
            issues[index].status = transition.to
            try await api.sendVoid(IssueEndpoints.ApplyTransition(issueKey: key, transitionID: transition.id))
            toaster?.success("Moved \(key) to \(StatusNormaliser.normalise(transition.to.name))")
        } catch {
            if let i = issues.firstIndex(where: { $0.key == key }) { issues[i] = snapshot }
            toaster?.error("Couldn't move \(key): \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private static func key(for projectKey: String) -> String {
        "issues.sprintSelection.\(projectKey)"
    }

    private static func persistSprintSelection(_ ids: Set<String>, projectKey: String) {
        UserDefaults.standard.set(Array(ids), forKey: key(for: projectKey))
    }

    private static func restoreSprintSelection(projectKey: String) -> Set<String> {
        let arr = UserDefaults.standard.array(forKey: key(for: projectKey)) as? [String] ?? []
        return Set(arr)
    }
}
