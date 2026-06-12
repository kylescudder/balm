import SwiftUI
import BalmModels
import BalmDesignSystem

struct IssueCardView: View {
    @Environment(\.balmTheme) private var theme
    let issue: JiraIssue

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.xs) {
                if let icon = issue.issueType.iconUrl {
                    AsyncImage(url: icon) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFit() } else { Color.clear }
                    }
                    .frame(width: 14, height: 14)
                }
                Text(issue.key)
                    .font(theme.typography.caption.monospaced())
                    .foregroundStyle(theme.palette.mutedForeground)
                Spacer()
                if let icon = issue.priority.iconUrl {
                    AsyncImage(url: icon) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFit() } else { Color.clear }
                    }
                    .frame(width: 14, height: 14)
                }
            }

            Text(issue.summary)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.foreground)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !issue.labels.isEmpty {
                FlexibleStack(spacing: theme.spacing.xs) {
                    ForEach(issue.labels.prefix(4), id: \.self) { BalmChip($0) }
                }
            }

            HStack(spacing: theme.spacing.xs) {
                if !issue.components.isEmpty {
                    Text(issue.components.first?.name ?? "")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.mutedForeground)
                        .lineLimit(1)
                    if issue.components.count > 1 {
                        Text("+\(issue.components.count - 1)")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.mutedForeground)
                    }
                }
                Spacer()
                if let assignee = issue.assignee {
                    AvatarView(name: assignee.displayName, avatarURL: assignee.avatarURL, size: 22)
                }
            }
        }
        .padding(theme.spacing.m)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
                .strokeBorder(theme.palette.border, lineWidth: 1)
        )
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
