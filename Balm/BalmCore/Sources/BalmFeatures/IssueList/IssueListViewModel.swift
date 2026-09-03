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

    public enum SearchState: Equatable, Sendable {
        case idle
        case searching
        case loaded
        case failed(String)
    }

    public let project: JiraProject
    public private(set) var issues: [JiraIssue] = []
    public private(set) var availableSprints: [JiraSprint] = []
    public private(set) var selectedSprintIDs: Set<String> = []
    public private(set) var userDefinition: FilterDefinition = .empty
    public private(set) var loadState: LoadState = .idle

    /// Instance-wide search hits for the current search term — issues that match
    /// the query regardless of project, sprint, or filter scope, so a ticket
    /// that isn't in the loaded view still surfaces. Populated by `search`, shown
    /// under a "More results" divider (minus anything already in view).
    public private(set) var globalResults: [JiraIssue] = []
    public private(set) var searchState: SearchState = .idle

    /// Dropdown pools for the filter sheet. Derived from the issues in the
    /// current sprint context *before* user filters are applied, so the menus
    /// keep offering every value (you can widen a filter without clearing it).
    public private(set) var filterOptions: AvailableFilterOptions = .empty
    /// The sprint set `filterOptions` was last built for — lets us skip the
    /// extra unfiltered fetch when only the user filters changed.
    private var filterOptionsSprints: Set<String>?

    /// Project-level component/version lists, fetched once and folded into the
    /// filter pools so those filters offer every project value — not just the
    /// ones present on loaded issues.
    private var projectComponentNames: [String] = []
    private var projectVersions: [JiraVersion] = []
    private var projectInstanceNames: [String] = []
    /// The Instance/Database custom field id resolved from create-metadata
    /// (e.g. `customfield_10801`). Authoritative and project-scoped — threaded
    /// into the JQL builder so the Instance filter targets the right `cf[N]`.
    private var projectInstanceFieldID: String?
    private var projectMetadataLoaded = false
    /// The JQL field that actually holds components for this project — the
    /// standard `component`, or a tenant custom select like `cf[10312]`,
    /// resolved from create-metadata. Threaded into the JQL builder.
    private var componentFieldJQL = "component"

    /// Issues grouped into status columns, ordered for the Kanban board. The
    /// pinned workflow columns come first in their fixed order (To Do, Blocked,
    /// Iteration Required, In Progress, Current Active Issue); everything else
    /// follows the list's grouping: health, then how far along the glyph is,
    /// then statusCategory precedence, then alphabetically.
    public var columns: [BoardColumn] {
        Self.columns(from: issues)
    }

    /// Issues grouped by health for the list, in `StatusHealth.allCases` order:
    /// blocked first, then in progress, waiting, to do, done, closed. Order
    /// within a group is the fetch order.
    public var healthSections: [IssueHealthSection] {
        Self.healthSections(from: issues)
    }

    nonisolated static func healthSections(from issues: [JiraIssue]) -> [IssueHealthSection] {
        let grouped = Dictionary(grouping: issues) { StatusNormaliser.health($0.status.name) }
        return StatusHealth.allCases.compactMap { health in
            grouped[health].map { IssueHealthSection(health: health, issues: $0) }
        }
    }

    nonisolated static func columns(from issues: [JiraIssue]) -> [BoardColumn] {
        let grouped = Dictionary(grouping: issues) { issue in
            StatusNormaliser.normalise(issue.status.name)
        }
        let categoryPrecedence = ["new": 0, "indeterminate": 1, "done": 2]

        let healthOrder = StatusHealth.allCases
        let sortedKeys: [String] = grouped.keys.sorted { lhs, rhs in
            let lPin = StatusNormaliser.pinnedColumnIndex(lhs) ?? Int.max
            let rPin = StatusNormaliser.pinnedColumnIndex(rhs) ?? Int.max
            if lPin != rPin { return lPin < rPin }

            let lg = StatusNormaliser.glyph(for: lhs)
            let rg = StatusNormaliser.glyph(for: rhs)
            let lh = healthOrder.firstIndex(of: lg.health) ?? healthOrder.count
            let rh = healthOrder.firstIndex(of: rg.health) ?? healthOrder.count
            if lh != rh { return lh < rh }

            // Within a health group, less progress comes first: In Progress
            // before In PR before In Review.
            let lf = lg.fill.fraction ?? 0
            let rf = rg.fill.fraction ?? 0
            if lf != rf { return lf < rf }

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
    private var searchTask: Task<Void, Never>?
    /// The trimmed query `globalResults` were fetched for — used to detect when
    /// the live text has moved on and the committed results are stale.
    private var committedQuery: String?

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
                if error.isCancellation { return }
                // Kanban boards have no sprints (`/sprint` returns 400). That's
                // expected, not an error — fall back to backlog, which lists
                // every issue not in a sprint (i.e. all of them). No toast.
                useBacklogOnly()
                return
            }
            availableSprints = [JiraSprint.backlog] + sprintsResponse.values
            dropFinishedSprintsFromSelection()

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
            // The view went away mid-load; nothing to report.
            if error.isCancellation { return }
            // No board / no permission / network blip — fall back to backlog so
            // the user at least has something, and surface the failure.
            useBacklogOnly()
            toaster?.report(error, "Sprints unavailable")
        }
    }

    private func useBacklogOnly() {
        availableSprints = [JiraSprint.backlog]
        if selectedSprintIDs.isEmpty {
            selectedSprintIDs = [JiraSprint.backlog.name]
        }
    }

    /// A remembered sprint that has since been completed is no longer offered
    /// by Jira. Drop it quietly, show the backlog if nothing else is selected,
    /// and tell the user once so they pick a new sprint.
    private func dropFinishedSprintsFromSelection() {
        let result = Self.reconciledSprintSelection(selectedSprintIDs, available: availableSprints)
        guard !result.removed.isEmpty else { return }
        selectedSprintIDs = result.kept
        Self.persistSprintSelection(result.kept, projectKey: project.key)
        let finished = result.removed.sorted().joined(separator: ", ")
        if result.kept == [JiraSprint.backlog.name] {
            toaster?.info("\(finished) has finished. Showing the backlog until you pick a new sprint.")
        } else {
            toaster?.info("\(finished) has finished and was removed from your selection.")
        }
    }

    /// Keeps the selected entries that still name or identify an available
    /// sprint; if none remain, falls back to the backlog.
    nonisolated static func reconciledSprintSelection(
        _ selected: Set<String>,
        available: [JiraSprint]
    ) -> (kept: Set<String>, removed: Set<String>) {
        let names = Set(available.map(\.name))
        let ids = Set(available.map(\.id))
        let kept = selected.filter { names.contains($0) || ids.contains($0) }
        let removed = selected.subtracting(kept)
        if kept.isEmpty && !removed.isEmpty {
            return ([JiraSprint.backlog.name], removed)
        }
        return (kept, removed)
    }

    public func setSprintSelection(_ ids: Set<String>) {
        selectedSprintIDs = ids
        Self.persistSprintSelection(ids, projectKey: project.key)
        reload()
    }

    public func setUserDefinition(_ definition: FilterDefinition) {
        guard userDefinition != definition else { return }
        userDefinition = definition
        reload()
    }

    /// The selected sprints resolved to their names — the scope passed to the
    /// JQL builder. Mirrors the resolution in `performLoad`; used by the filter
    /// sheet's Advanced-JQL preview.
    public var selectedSprintNames: [String] {
        availableSprints
            .filter { selectedSprintIDs.contains($0.name) || selectedSprintIDs.contains($0.id) }
            .map(\.name)
    }

    public func reload() {
        let names = selectedSprintNames
        let key = IssueListCacheKey(projectID: project.id, sprintNames: names, definition: userDefinition)
        if let cached = SharedIssueListCache.issues(for: key) {
            issues = cached
            loadState = .loaded
            refreshInBackground()
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(showLoading: true)
        }
    }

    public func refreshInBackground() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(showLoading: false)
        }
    }

    /// Awaitable reload for `.refreshable` — keeps the pull-to-refresh spinner
    /// on screen until the fetch actually resolves.
    public func reloadAwaiting() async {
        loadTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.performLoad(showLoading: true)
        }
        loadTask = task
        await task.value
    }

    private func performLoad(showLoading: Bool) async {
        let names = selectedSprintNames
        if showLoading || issues.isEmpty {
            loadState = .loading
        }
        guard !names.isEmpty else {
            if showLoading || issues.isEmpty {
                issues = []
                filterOptions = .empty
                filterOptionsSprints = nil
                loadState = .loaded
            }
            return
        }
        // A restored component or instance filter needs its resolved JQL field
        // before the first fetch, or it would target the wrong field (instance)
        // or error (components).
        if Self.usesResolvedField(userDefinition) {
            await loadProjectMetadataIfNeeded()
        }
        do {
            let fresh = try await api.issues(
                projectKey: project.key,
                sprints: names,
                definition: userDefinition,
                componentField: componentFieldJQL,
                instanceField: projectInstanceFieldID
            )
            try Task.checkCancellation()
            let next = IssueListRefreshPolicy.replacementIssues(
                current: issues,
                fresh: fresh,
                isUserVisibleRefresh: showLoading
            )
            issues = next
            SharedIssueListCache.store(
                next,
                for: IssueListCacheKey(projectID: project.id, sprintNames: names, definition: userDefinition)
            )
            loadState = .loaded
        } catch {
            if error.isCancellation { return }
            if showLoading || issues.isEmpty {
                loadState = .failed(error.localizedDescription)
            } else {
                toaster?.report(error, "Couldn't refresh issues")
            }
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
        await loadProjectMetadataIfNeeded()
        let key = Set(sprintNames)
        if userDefinition.isEmpty {
            filterOptions = AvailableFilterOptions.from(
                issues,
                extraComponents: projectComponentNames,
                extraReleases: projectVersions,
                extraInstanceNames: projectInstanceNames
            )
            filterOptionsSprints = key
            return
        }
        guard filterOptionsSprints != key else { return }
        if let all = try? await api.issues(projectKey: project.key, sprints: sprintNames, definition: .empty) {
            filterOptions = AvailableFilterOptions.from(
                all,
                extraComponents: projectComponentNames,
                extraReleases: projectVersions,
                extraInstanceNames: projectInstanceNames
            )
            filterOptionsSprints = key
        }
    }

    /// Resolve, once and best-effort, the project's version list (for the
    /// Release pool) and its component field — both which JQL field holds
    /// components (standard `component` vs a custom select) and that field's
    /// full value list, via create-metadata.
    private func loadProjectMetadataIfNeeded() async {
        guard !projectMetadataLoaded else { return }
        async let versionsTask = api.send(ProjectEndpoints.Versions(projectKeyOrId: project.key))
        async let metaTask = resolveCreateMetaFields()
        let versions = try? await versionsTask
        let meta = await metaTask
        // Everything threw (e.g. transient network) — leave unmarked so a later
        // reload retries. Any successful response counts as loaded.
        guard versions != nil || meta.component != nil || meta.instance != nil else { return }
        projectVersions = versions ?? []
        projectInstanceNames = meta.instance?.values ?? []
        projectInstanceFieldID = meta.instance?.fieldId
        if let component = meta.component {
            componentFieldJQL = component.jqlField
            projectComponentNames = component.values
        }
        projectMetadataLoaded = true
    }

    /// One create-metadata pass over the project's first few issue types,
    /// pulling out both the component field (its JQL name + value list — the
    /// standard `components` or a tenant custom select) and the Instance /
    /// Database field's full option list. Single source so metadata isn't
    /// fetched twice. The Instance field's `allowedValues` is the complete,
    /// uncapped option set — independent of which values appear on issues.
    private func resolveCreateMetaFields() async
        -> (component: (jqlField: String, values: [String])?,
            instance: (fieldId: String, values: [String])?) {
        guard let types = try? await api.send(MetadataEndpoints.ProjectIssueTypes(projectID: project.id)) else {
            return (nil, nil)
        }
        var component: (jqlField: String, values: [String])?
        var instanceFieldID: String?
        var instanceNames = Set<String>()
        for type in types.prefix(5) {
            guard let id = type.id,
                  let meta = try? await api.send(
                    MetadataEndpoints.CreateMetaFields(projectIdOrKey: project.key, issueTypeId: id)
                  )
            else { continue }
            if component == nil {
                component = MetadataEndpoints.CreateMetaFields.resolveComponentField(from: meta.fields)
            }
            if let instance = MetadataEndpoints.CreateMetaFields.resolveInstanceField(from: meta.fields) {
                instanceFieldID = instance.fieldId
                instanceNames.formUnion(instance.values)
            }
        }
        let instance = instanceFieldID.map {
            (fieldId: $0, values: instanceNames.sorted { $0.localizedCompare($1) == .orderedAscending })
        }
        return (component, instance)
    }

    /// Whether a structured definition filters on a field whose JQL name must be
    /// resolved from create-metadata before querying — components (custom select
    /// vs standard) or the tenant's Instance/Database custom field. Raw JQL is
    /// passed through untouched, so it never needs resolution.
    private static func usesResolvedField(_ definition: FilterDefinition) -> Bool {
        guard case .structured(let group) = definition else { return false }
        func walk(_ group: FilterGroup) -> Bool {
            for row in group.rows {
                switch row.node {
                case .condition(let c) where c.field == .components || c.field == .instanceName:
                    return true
                case .condition: continue
                case .group(let sub): if walk(sub) { return true }
                }
            }
            return false
        }
        return walk(group)
    }

    /// Run an instance-wide search for `query` (title / body / comments / exact
    /// key) and publish the hits to `globalResults`. Independent of the sprint
    /// and filter scope, so it surfaces matches that aren't in the loaded view.
    /// A blank query clears any prior results.
    public func search(_ query: String) async {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clearSearch(); return }
        committedQuery = trimmed
        searchState = .searching
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await self.api.searchIssues(matching: trimmed)
                if Task.isCancelled { return }
                self.globalResults = results
                self.searchState = .loaded
            } catch {
                if Task.isCancelled || error.isCancellation { return }
                self.searchState = .failed(error.localizedDescription)
            }
        }
        searchTask = task
        await task.value
    }

    /// Drop the committed results when the live query no longer matches the term
    /// they were fetched for, so a newer term never shows stale instance-wide
    /// hits (or leaves them up after a failed direct-key lookup). A no-op while
    /// idle or while the query is unchanged.
    public func invalidateSearchIfQueryChanged(_ query: String) {
        guard searchState != .idle else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != committedQuery { clearSearch() }
    }

    /// Drop any global search results and reset the search UI to idle — called
    /// when the search field is emptied or dismissed.
    public func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        committedQuery = nil
        globalResults = []
        searchState = .idle
    }

    /// Fetch a single issue by key for the ⌘K go-to-ticket flow — works even
    /// when the issue isn't in the currently loaded view. Toasts and returns
    /// nil on failure (e.g. unknown key), unless `notifyFailure` is false.
    public func fetchIssue(key: String, notifyFailure: Bool = true) async -> JiraIssue? {
        do {
            let instanceField = await api.resolveInstanceFieldID()
            let raw = try await api.send(IssueEndpoints.GetDetail(issueKey: key))
            return IssueDetailMapper.decode(raw, instanceFieldID: instanceField).0
        } catch {
            if notifyFailure {
                toaster?.error("Couldn't open \(key): \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Refresh the view after creating `key`. The JQL search backing the list
    /// is eventually consistent, so a plain reload can miss a just-created
    /// issue — fetch it directly by key (strongly consistent) and pin it to
    /// the top if the search results don't include it yet.
    @discardableResult
    public func refreshAfterCreate(key: String) async -> JiraIssue? {
        let created = await fetchIssue(key: key, notifyFailure: false)
        await reloadAwaiting()
        if let created, !issues.contains(where: { $0.key == created.key }) {
            issues.insert(created, at: 0)
        }
        return created ?? issues.first { $0.key == key }
    }

    /// Apply an issue change broadcast by the detail screen (status, assignee,
    /// sprint, …) so the matching board/list card updates immediately — columns
    /// recompute off `issues`, so a status change re-buckets the card at once.
    public func applyExternalUpdate(_ issue: JiraIssue) {
        if let index = issues.firstIndex(where: { $0.key == issue.key }) {
            issues[index] = issue
        }
        SharedIssueListCache.update(issue)
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

/// One grouped section of the issue list.
public struct IssueHealthSection: Identifiable, Sendable, Hashable {
    public let health: StatusHealth
    public let issues: [JiraIssue]
    public var id: StatusHealth { health }
}
