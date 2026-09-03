import SwiftUI
import BalmModels
import BalmDesignSystem

/// One issue, one line: glyph, key, priority, summary, labels, assignee. On a
/// compact iPhone width the summary gets two lines and the key drops
/// underneath. Everything beyond this belongs in the inspector.
struct IssueRowView: View {
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    let issue: JiraIssue

    var body: some View {
        Group {
            if isCompact {
                twoLine
            } else {
                oneLine
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var oneLine: some View {
        HStack(spacing: 10) {
            StatusGlyph(issue.status.name, size: 14)
            Text(issue.key)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 72, alignment: .leading)
            PriorityIcon(priority: issue.priority, size: 14)
            Text(issue.summary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            ForEach(issue.labels.prefix(3), id: \.self) { LabelTag(text: $0) }
            assignee(size: 20)
        }
        .padding(.vertical, 2)
    }

    private var twoLine: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusGlyph(issue.status.name, size: 16)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.summary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(issue.key)
                        .monospacedDigit()
                    ForEach(issue.labels.prefix(2), id: \.self) { Text($0) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            assignee(size: 24)
                .padding(.top, 1)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func assignee(size: CGFloat) -> some View {
        if let assignee = issue.assignee {
            AvatarView(name: assignee.displayName, avatarURL: assignee.avatarURL, size: size)
        } else {
            UnassignedAvatar(size: size)
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(issue.key), \(issue.summary)"]
        parts.append("status \(StatusNormaliser.normalise(issue.status.name))")
        if !issue.priority.name.isEmpty { parts.append("priority \(issue.priority.name)") }
        if let assignee = issue.assignee {
            parts.append("assigned to \(assignee.displayName)")
        } else {
            parts.append("unassigned")
        }
        if !issue.labels.isEmpty { parts.append("labels: \(issue.labels.joined(separator: ", "))") }
        return parts.joined(separator: ". ")
    }
}
