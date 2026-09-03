import SwiftUI

/// What the inspector or detail column shows when nothing is selected. The
/// empty state is where the keyboard model gets taught, so on the Mac it
/// lists the keys that reach every place in the app.
struct EmptyInspectorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Nothing selected", systemImage: "sidebar.trailing")
        } description: {
            Text("Pick an issue, or move through the list with the arrow keys.")
        } actions: {
            #if os(macOS)
            KeyHints()
                .padding(.top, 8)
            #endif
        }
    }
}

/// The shortcut cheat sheet: the keys that move around, then the keys that
/// act on an open issue.
struct KeyHints: View {
    private let viewHints: [(keys: [String], action: String)] = [
        (["N"], "New issue"),
        (["F"], "Filter"),
        (["⇧", "S"], "Sprint"),
        (["I"], "Inbox"),
        (["⌘", "K"], "Search issues"),
        (["1", "2"], "List, board")
    ]

    private let issueHints: [(keys: [String], action: String)] = [
        (["S"], "Status"),
        (["A"], "Assignee"),
        (["P"], "Priority"),
        (["L"], "Labels"),
        (["D"], "Due date"),
        (["C"], "Comment"),
        (["E"], "Edit description")
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            grid(viewHints)
            VStack(alignment: .leading, spacing: 8) {
                Text("With an issue open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                grid(issueHints)
            }
        }
        .font(.callout)
    }

    private func grid(_ hints: [(keys: [String], action: String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                GridRow {
                    HStack(spacing: 4) {
                        ForEach(hint.keys, id: \.self) { Keycap($0) }
                    }
                    .gridColumnAlignment(.leading)
                    Text(hint.action)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Keycap: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .frame(minWidth: 22)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(key)
    }
}
