import SwiftUI

#if os(macOS)
public struct BalmCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Issue") {
                post(.balmCreateIssueRequested)
            }
            .keyboardShortcut("c", modifiers: [])
        }

        CommandMenu("View") {
            Button("Toggle Filters") { post(.balmToggleFiltersRequested) }
                .keyboardShortcut("f", modifiers: [])
        }

        CommandMenu("Issue") {
            Button("Refresh") { post(.balmRefreshIssuesRequested) }
                .keyboardShortcut("r", modifiers: [.command])
            Divider()
            Button("New Issue…") { post(.balmCreateIssueRequested) }
                .keyboardShortcut("c", modifiers: [])
        }

        CommandMenu("Go") {
            Button("Search…") { post(.balmSearchRequested) }
                .keyboardShortcut("k", modifiers: [.command])
            Button("Go to Inbox") { post(.balmGoToInboxRequested) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appInfo) {
            Button("Change Project…") { post(.balmChangeProjectRequested) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Sign Out") { post(.balmSignOutRequested) }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
#endif

public extension Notification.Name {
    static let balmCreateIssueRequested = Notification.Name("app.balm.createIssueRequested")
    static let balmToggleFiltersRequested = Notification.Name("app.balm.toggleFiltersRequested")
    static let balmSearchRequested = Notification.Name("app.balm.searchRequested")
    static let balmRefreshIssuesRequested = Notification.Name("app.balm.refreshIssuesRequested")
    static let balmSignOutRequested = Notification.Name("app.balm.signOutRequested")
    static let balmChangeProjectRequested = Notification.Name("app.balm.changeProjectRequested")
    /// Broadcast by the issue detail VM after a successful mutation so the board
    /// / list can update the matching card immediately. userInfo["issue"].
    static let balmIssueUpdated = Notification.Name("app.balm.issueUpdated")
    /// Requests the shell present the Inbox sheet (⇧⌘I on macOS).
    static let balmGoToInboxRequested = Notification.Name("app.balm.goToInboxRequested")
}
