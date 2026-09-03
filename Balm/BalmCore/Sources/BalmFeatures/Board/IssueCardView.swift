import SwiftUI
import BalmModels
import BalmDesignSystem

/// A board card: key and priority, summary, labels and assignee. It lifts off
/// the window background with a hairline shadow and carries no status of its
/// own, because the column header already says where it is.
struct IssueCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let issue: JiraIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(issue.key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                PriorityIcon(priority: issue.priority, size: 12)
            }

            Text(issue.summary)
                .font(.body)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(issue.labels.prefix(3), id: \.self) { LabelTag(text: $0) }
                Spacer(minLength: 0)
                if let assignee = issue.assignee {
                    AvatarView(name: assignee.displayName, avatarURL: assignee.avatarURL, size: 20)
                } else {
                    UnassignedAvatar(size: 20)
                }
            }
        }
        .padding(12)
        // A material rather than a fixed colour: it lifts off the window in
        // both appearances, where a plain system background colour reads as
        // white in light mode and disappears into the window in dark mode.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.07), radius: colorScheme == .dark ? 3 : 1.5, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts: [String] = ["\(issue.key), \(issue.summary)"]
        parts.append("status \(StatusNormaliser.normalise(issue.status.name))")
        parts.append("priority \(issue.priority.name)")
        if let assignee = issue.assignee {
            parts.append("assigned to \(assignee.displayName)")
        } else {
            parts.append("unassigned")
        }
        if !issue.labels.isEmpty {
            parts.append("labels: \(issue.labels.joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }
}
