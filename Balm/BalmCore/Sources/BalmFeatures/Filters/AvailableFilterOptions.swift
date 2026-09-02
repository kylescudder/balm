import Foundation
import BalmModels

/// Filter option pools derived from the issues currently loaded. Matches the web
/// pattern of building the dropdown contents from the visible set — cheaper than
/// extra API calls and inherently scoped to the project + sprint context.
public struct AvailableFilterOptions: Sendable, Equatable {
    public struct NamedOption: Sendable, Hashable, Identifiable {
        public let id: String
        public let displayName: String
        public init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    public var statuses: [String]
    public var priorities: [String]
    public var issueTypes: [String]
    public var assignees: [NamedOption]
    public var reporters: [NamedOption]
    public var labels: [String]
    public var components: [String]
    public var releases: [NamedOption]
    public var instanceNames: [String]

    public init(
        statuses: [String] = [],
        priorities: [String] = [],
        issueTypes: [String] = [],
        assignees: [NamedOption] = [],
        reporters: [NamedOption] = [],
        labels: [String] = [],
        components: [String] = [],
        releases: [NamedOption] = [],
        instanceNames: [String] = []
    ) {
        self.statuses = statuses
        self.priorities = priorities
        self.issueTypes = issueTypes
        self.assignees = assignees
        self.reporters = reporters
        self.labels = labels
        self.components = components
        self.releases = releases
        self.instanceNames = instanceNames
    }

    public static let empty = AvailableFilterOptions()

    /// Derive the dropdown pools from the currently loaded issues.
    /// Adds the `UNASSIGNED` and `NO_RELEASE` sentinels so they always appear.
    ///
    /// `extraComponents` / `extraReleases` fold in the project's full component
    /// and version lists (fetched separately), so those filters offer every
    /// project value — not just the ones that happen to appear on loaded issues.
    public static func from(
        _ issues: [JiraIssue],
        extraComponents: [String] = [],
        extraReleases: [JiraVersion] = [],
        extraInstanceNames: [String] = []
    ) -> AvailableFilterOptions {
        let statuses = Self.unique(issues.map(\.status.name))
        let priorities = Self.unique(issues.map(\.priority.name))
        let issueTypes = Self.unique(issues.map(\.issueType.name))

        var assignees: [NamedOption] = [
            NamedOption(id: FilterOptions.unassignedSentinel, displayName: "Unassigned")
        ]
        var seenAssignee = Set<String>()
        for issue in issues {
            guard let a = issue.assignee else { continue }
            let id = a.displayName
            if seenAssignee.insert(id).inserted {
                assignees.append(NamedOption(id: id, displayName: a.displayName))
            }
        }

        var reporters: [NamedOption] = []
        var seenReporter = Set<String>()
        for issue in issues {
            guard let r = issue.reporter else { continue }
            let id = r.displayName
            if seenReporter.insert(id).inserted {
                reporters.append(NamedOption(id: id, displayName: r.displayName))
            }
        }

        let labels = Self.unique(issues.flatMap(\.labels))
        let components = Self.unique(issues.flatMap { $0.components.map(\.name) } + extraComponents)
        let instanceNames = Self.unique(issues.compactMap(\.instanceName) + extraInstanceNames)

        var releases: [NamedOption] = [
            NamedOption(id: JiraVersion.noReleaseSentinel, displayName: "No release")
        ]
        var seenRelease = Set<String>()
        let releaseNames = issues.flatMap { $0.fixVersions.map(\.name) } + extraReleases.map(\.name)
        for name in releaseNames where seenRelease.insert(name).inserted {
            releases.append(NamedOption(id: name, displayName: name))
        }

        return AvailableFilterOptions(
            statuses: statuses,
            priorities: priorities,
            issueTypes: issueTypes,
            assignees: assignees,
            reporters: reporters,
            labels: labels,
            components: components,
            releases: releases,
            instanceNames: instanceNames
        )
    }

    /// The pool to present in the filter menus: the unfiltered `snapshot` unioned
    /// with `loaded` — the values on the issues currently on screen.
    ///
    /// The snapshot is refreshed only when the sprint set changes, so it can
    /// predate what is on the board; folding in `loaded` keeps a visible value
    /// selectable regardless. Callers pass `.empty` for `loaded` when nothing is
    /// loaded, so both being empty means no sprint is selected or a load is
    /// still in flight — the menus should read "No values" rather than offer
    /// bare `UNASSIGNED` / `NO_RELEASE` sentinels.
    public static func presented(
        snapshot: AvailableFilterOptions,
        loaded: AvailableFilterOptions
    ) -> AvailableFilterOptions {
        guard snapshot != .empty || loaded != .empty else { return .empty }
        return snapshot.merging(loaded)
    }

    /// Union this pool with `other`, keeping this value's ordering and appending
    /// anything only `other` has.
    ///
    /// Used to fold the currently-loaded issues into the unfiltered snapshot, so
    /// a value that is visibly on the board is always selectable in the filter
    /// menus even when the snapshot predates it (a status reached mid-sprint,
    /// a newly added label, an assignee who joined the sprint late).
    public func merging(_ other: AvailableFilterOptions) -> AvailableFilterOptions {
        AvailableFilterOptions(
            statuses: Self.unique(statuses + other.statuses),
            priorities: Self.unique(priorities + other.priorities),
            issueTypes: Self.unique(issueTypes + other.issueTypes),
            assignees: Self.mergedNamed(assignees, other.assignees),
            reporters: Self.mergedNamed(reporters, other.reporters),
            labels: Self.unique(labels + other.labels),
            components: Self.unique(components + other.components),
            releases: Self.mergedNamed(releases, other.releases),
            instanceNames: Self.unique(instanceNames + other.instanceNames)
        )
    }

    /// Dedupe by `id`, preserving `lhs`'s order (so the `UNASSIGNED` /
    /// `NO_RELEASE` sentinels stay first) and appending `rhs`'s extras.
    private static func mergedNamed(_ lhs: [NamedOption], _ rhs: [NamedOption]) -> [NamedOption] {
        var seen = Set<String>()
        var out: [NamedOption] = []
        for option in lhs + rhs where seen.insert(option.id).inserted {
            out.append(option)
        }
        return out
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in values where !v.isEmpty {
            if seen.insert(v).inserted { out.append(v) }
        }
        return out.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}
