import Foundation

/// Direct port of `lib/utils.ts:8-159` (`normalizeStatusName`, `getStatusGroupRank`).
/// Maps Jira status name variations to a canonical group label used by the UI.
public enum StatusNormaliser {
    private static let map: [String: String] = [
        // To Do
        "to do": "To Do",
        "todo": "To Do",
        "open": "To Do",
        "new": "To Do",
        "backlog": "To Do",
        // Attention Needed
        "attention needed": "Attention Needed",
        // Blocked
        "blocked": "Blocked",
        "blocking": "Blocked",
        "impediment": "Blocked",
        "stuck": "Blocked",
        // In Progress
        "in progress": "In Progress",
        "inprogress": "In Progress",
        // Current Active Issue
        "current active issue": "Current Active Issue",
        // In PR
        "in pr": "In PR",
        "pull request": "In PR",
        "pr submitted": "In PR",
        "pr review": "In PR",
        "pull request review": "In PR",
        // In Review
        "in review": "In Review",
        "code review": "In Review",
        "review": "In Review",
        // Awaiting Testing
        "awaiting testing": "Awaiting Testing",
        "waiting for test": "Awaiting Testing",
        "ready for testing": "Awaiting Testing",
        "pending test": "Awaiting Testing",
        // Iteration Required
        "iteration required": "Iteration Required",
        "needs iteration": "Iteration Required",
        "requires iteration": "Iteration Required",
        "iteration needed": "Iteration Required",
        // Awaiting Information
        "awaiting information": "Awaiting Information",
        "waiting for info": "Awaiting Information",
        "needs information": "Awaiting Information",
        "pending information": "Awaiting Information",
        "awaiting info": "Awaiting Information",
        // Under Monitoring
        "under monitoring": "Under Monitoring",
        "monitoring": "Under Monitoring",
        "being monitored": "Under Monitoring",
        // For Product Prioritisation
        "for product prioritisation": "For Product Prioritisation",
        // Not an Issue
        "not an issue": "Not an Issue",
        "invalid": "Not an Issue",
        "not a bug": "Not an Issue",
        "won't fix": "Not an Issue",
        "wont fix": "Not an Issue",
        // Requires Config Change
        "requires a config change": "Requires Config Change",
        "requires config change": "Requires Config Change",
        "config change": "Requires Config Change",
        "configuration change": "Requires Config Change",
        "needs config": "Requires Config Change",
        // Done
        "done": "Done",
        "closed": "Done",
        "resolved": "Done",
        "complete": "Done",
        "completed": "Done",
        // Declined
        "declined": "Declined",
        "rejected": "Declined",
        "cancelled": "Declined",
        "canceled": "Declined",
        // Duplicate
        "duplicate": "Duplicate",
        "duplicated": "Duplicate"
    ]

    public static func normalise(_ status: String) -> String {
        map[status.lowercased()] ?? status
    }

    /// Returns 0 (grey), 1 (blue/working), 2 (green/done), 3 (unknown).
    public static func groupRank(_ status: String) -> Int {
        let s = normalise(status).lowercased()
        let grey: Set<String> = ["to do", "awaiting testing", "for product prioritisation"]
        let blue: Set<String> = [
            "in progress", "iteration required", "blocked",
            "current active issue", "in pr", "awaiting information", "under monitoring"
        ]
        let green: Set<String> = ["done", "requires config change", "not an issue", "declined", "duplicate"]
        if grey.contains(s) { return 0 }
        if blue.contains(s) { return 1 }
        if green.contains(s) { return 2 }
        return 3
    }

    /// Maps a (normalised) status to a semantic colour token name in the design system.
    /// Keep this in sync with `lib/utils.ts:99-159` (`getStatusColor`).
    public static func semanticTokenName(_ status: String) -> StatusSemanticToken {
        let s = normalise(status).lowercased()
        switch s {
        case "attention needed", "blocked":
            return .destructive
        case "in progress":
            return .chart4
        case "current active issue", "in pr", "in review", "iteration required":
            return .primary
        case "awaiting testing", "under monitoring":
            return .chart1
        case "to do", "awaiting information", "for product prioritisation":
            return .chart3
        case "done", "requires config change", "not an issue", "declined", "duplicate":
            return .chart5
        default:
            return .neutral
        }
    }
}

public enum StatusSemanticToken: String, Sendable {
    case primary
    case destructive
    case chart1
    case chart3
    case chart4
    case chart5
    case neutral
}
