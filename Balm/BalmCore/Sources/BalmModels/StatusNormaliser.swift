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

    /// The glyph that stands in for a status everywhere Balm shows one: a ring
    /// whose fill shows how far along the issue is and whose health picks the
    /// colour. Unknown statuses get an empty neutral ring and keep their own
    /// name in text.
    public static func glyph(for status: String) -> StatusGlyphSpec {
        switch normalise(status).lowercased() {
        case "to do":
            return StatusGlyphSpec(health: .notStarted, fill: .none, mark: .none)
        case "for product prioritisation":
            return StatusGlyphSpec(health: .notStarted, fill: .dotted, mark: .none)
        case "in progress", "current active issue", "iteration required":
            return StatusGlyphSpec(health: .active, fill: .half, mark: .none)
        case "in pr", "in review":
            return StatusGlyphSpec(health: .active, fill: .threeQuarters, mark: .none)
        case "awaiting information":
            return StatusGlyphSpec(health: .waiting, fill: .half, mark: .none)
        case "awaiting testing", "under monitoring":
            return StatusGlyphSpec(health: .waiting, fill: .threeQuarters, mark: .none)
        case "blocked", "attention needed":
            return StatusGlyphSpec(health: .blocked, fill: .none, mark: .exclamation)
        case "done", "requires config change":
            return StatusGlyphSpec(health: .done, fill: .full, mark: .check)
        case "declined", "duplicate", "not an issue":
            return StatusGlyphSpec(health: .closed, fill: .none, mark: .cross)
        default:
            return StatusGlyphSpec(health: .notStarted, fill: .none, mark: .none)
        }
    }

    /// The health bucket a status falls into; drives list grouping and colour.
    public static func health(_ status: String) -> StatusHealth {
        glyph(for: status).health
    }

    /// Statuses whose board column position is fixed, in order. Anything not
    /// listed follows, ordered by health, then progress, then name.
    public static let pinnedColumnOrder: [String] = [
        "To Do",
        "Blocked",
        "Iteration Required",
        "In Progress",
        "Current Active Issue"
    ]

    /// Position of a status in `pinnedColumnOrder`, or nil when it is not pinned.
    public static func pinnedColumnIndex(_ status: String) -> Int? {
        pinnedColumnOrder.firstIndex(of: normalise(status))
    }
}

/// Where an issue sits in its life, independent of the exact Jira status name.
/// `allCases` is the display order for grouped lists and board columns: not
/// started first, then blocked, then moving, then waiting, then finished.
public enum StatusHealth: String, Sendable, Hashable, Codable, CaseIterable {
    case notStarted
    case blocked
    case active
    case waiting
    case done
    case closed

    public var title: String {
        switch self {
        case .blocked: return "Blocked"
        case .active: return "In progress"
        case .waiting: return "Waiting"
        case .notStarted: return "To do"
        case .done: return "Done"
        case .closed: return "Closed"
        }
    }

    /// The glyph used for a whole group of this health, e.g. a list section.
    public var representativeGlyph: StatusGlyphSpec {
        switch self {
        case .blocked: return StatusGlyphSpec(health: .blocked, fill: .none, mark: .exclamation)
        case .active: return StatusGlyphSpec(health: .active, fill: .half, mark: .none)
        case .waiting: return StatusGlyphSpec(health: .waiting, fill: .threeQuarters, mark: .none)
        case .notStarted: return StatusGlyphSpec(health: .notStarted, fill: .none, mark: .none)
        case .done: return StatusGlyphSpec(health: .done, fill: .full, mark: .check)
        case .closed: return StatusGlyphSpec(health: .closed, fill: .none, mark: .cross)
        }
    }
}

/// How much of the status ring is filled.
public enum StatusGlyphFill: Sendable, Hashable {
    case none
    case dotted
    case half
    case threeQuarters
    case full

    /// The filled fraction, or nil when there is nothing to fill.
    public var fraction: Double? {
        switch self {
        case .none, .dotted: return nil
        case .half: return 0.5
        case .threeQuarters: return 0.75
        case .full: return 1
        }
    }
}

/// A symbol drawn inside the ring.
public enum StatusGlyphMark: Sendable, Hashable {
    case none
    case check
    case exclamation
    case cross
}

/// Everything a view needs to draw a status glyph. Pure value; the design
/// system maps `health` to colour.
public struct StatusGlyphSpec: Sendable, Hashable {
    public let health: StatusHealth
    public let fill: StatusGlyphFill
    public let mark: StatusGlyphMark

    public init(health: StatusHealth, fill: StatusGlyphFill, mark: StatusGlyphMark) {
        self.health = health
        self.fill = fill
        self.mark = mark
    }
}
