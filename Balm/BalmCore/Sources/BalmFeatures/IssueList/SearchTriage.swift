import Foundation
import BalmModels

/// Why an instance-wide search hit was not in the loaded view. Attribution
/// runs from the widest scope inward: project, then sprint, then filter. A hit
/// that passes all three is in the view; the text match was in a field the
/// live filter does not search, or the view has not loaded it yet.
enum HiddenReason: Hashable {
    case otherProject(projectKey: String)
    /// `sprintName` is nil for the backlog.
    case outsideSprints(sprintName: String?)
    case filtered(FilterMismatch)
    case matchedElsewhere(loaded: Bool)

    var group: HiddenGroupKind {
        switch self {
        case .otherProject: return .otherProject
        case .outsideSprints: return .outsideSprints
        case .filtered: return .filtered
        case .matchedElsewhere: return .matchedElsewhere
        }
    }
}

enum FilterMismatch: Hashable {
    /// The specific top-level conditions the issue fails.
    case conditions([FilterCondition])
    /// A raw JQL filter that cannot be evaluated locally.
    case jql
    /// Failed a filter with OR joins or nested groups; no single culprit.
    case whole
}

/// Display order of the hidden groups: what the user can undo most easily first.
enum HiddenGroupKind: Hashable, CaseIterable {
    case filtered
    case outsideSprints
    case otherProject
    case matchedElsewhere

    var title: String {
        switch self {
        case .filtered: return "Hidden by your filters"
        case .outsideSprints: return "Outside your sprints"
        case .otherProject: return "In other projects"
        case .matchedElsewhere: return "Matched in comments or details"
        }
    }

    var systemImage: String {
        switch self {
        case .filtered: return "line.3.horizontal.decrease"
        case .outsideSprints: return "calendar"
        case .otherProject: return "folder"
        case .matchedElsewhere: return "text.bubble"
        }
    }
}

struct HiddenResult: Identifiable, Hashable {
    let issue: JiraIssue
    let reason: HiddenReason
    var id: String { issue.key }
}

struct HiddenGroup: Identifiable {
    let kind: HiddenGroupKind
    let results: [HiddenResult]
    var id: HiddenGroupKind { kind }
}

/// What the current view is scoped to, captured for triage.
struct SearchScope {
    let activeProjectKey: String
    let selectedSprintNames: [String]
    let loadedKeys: Set<String>
    let definition: FilterDefinition
}

enum SearchTriage {
    static func reason(for issue: JiraIssue, scope: SearchScope) -> HiddenReason {
        if issue.projectKey.caseInsensitiveCompare(scope.activeProjectKey) != .orderedSame {
            return .otherProject(projectKey: issue.projectKey)
        }
        if !isInSelectedSprints(issue, scope: scope) {
            return .outsideSprints(sprintName: issue.sprint?.name)
        }
        let loaded = scope.loadedKeys.contains(issue.key)
        switch FilterMatcher.matches(issue, scope.definition) {
        case .some(false):
            let failing = FilterMatcher.failingConditions(issue, in: scope.definition)
            return .filtered(failing.isEmpty ? .whole : .conditions(failing))
        case .none:
            return loaded ? .matchedElsewhere(loaded: true) : .filtered(.jql)
        case .some(true):
            return .matchedElsewhere(loaded: loaded)
        }
    }

    static func groups(for issues: [JiraIssue], scope: SearchScope) -> [HiddenGroup] {
        let results = issues.map { HiddenResult(issue: $0, reason: reason(for: $0, scope: scope)) }
        let grouped = Dictionary(grouping: results) { $0.reason.group }
        return HiddenGroupKind.allCases.compactMap { kind in
            grouped[kind].map { HiddenGroup(kind: kind, results: $0) }
        }
    }

    private static func isInSelectedSprints(_ issue: JiraIssue, scope: SearchScope) -> Bool {
        if let sprint = issue.sprint {
            return scope.selectedSprintNames.contains(sprint.name)
        }
        return scope.selectedSprintNames.contains(JiraSprint.backlog.name)
    }
}

/// The note the inspector shows above a hidden result: the reason in a
/// sentence, and the one action that would bring the issue into view.
public struct IssueVisibilityNote {
    public let systemImage: String
    public let text: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(systemImage: String, text: String, actionTitle: String?, action: (() -> Void)?) {
        self.systemImage = systemImage
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }
}
