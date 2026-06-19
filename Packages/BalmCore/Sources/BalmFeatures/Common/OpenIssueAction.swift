import SwiftUI
import BalmModels

/// Environment action for navigating to an issue, mirroring SwiftUI's own
/// `openURL`. Each shell wires it to its own navigation mechanism: the macOS
/// shell swaps the detail inspector's `selection`, the iOS shell pushes onto
/// the navigation path. Views that surface a tappable issue (e.g. linked
/// issues) call it without caring which platform they're on.
public struct OpenIssueAction {
    private let handler: (JiraIssue) -> Void

    public init(_ handler: @escaping (JiraIssue) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ issue: JiraIssue) {
        handler(issue)
    }
}

private struct OpenIssueActionKey: EnvironmentKey {
    static var defaultValue: OpenIssueAction { OpenIssueAction { _ in } }
}

public extension EnvironmentValues {
    var openIssue: OpenIssueAction {
        get { self[OpenIssueActionKey.self] }
        set { self[OpenIssueActionKey.self] = newValue }
    }
}
