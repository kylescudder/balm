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

    public init(
        statuses: [String] = [],
        priorities: [String] = [],
        issueTypes: [String] = [],
        assignees: [NamedOption] = [],
        reporters: [NamedOption] = [],
        labels: [String] = [],
        components: [String] = [],
        releases: [NamedOption] = []
    ) {
        self.statuses = statuses
        self.priorities = priorities
        self.issueTypes = issueTypes
        self.assignees = assignees
        self.reporters = reporters
        self.labels = labels
        self.components = components
        self.releases = releases
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
        extraReleases: [JiraVersion] = []
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
            releases: releases
        )
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
