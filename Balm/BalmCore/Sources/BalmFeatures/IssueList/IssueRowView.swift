import SwiftUI
import BalmModels
import BalmDesignSystem

struct IssueRowView: View {
    @Environment(\.balmTheme) private var theme
    let issue: JiraIssue

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                HStack(spacing: theme.spacing.s) {
                    Text(issue.key)
                        .font(theme.typography.caption.monospaced())
                        .foregroundStyle(theme.palette.mutedForeground)
                    BalmChip(StatusNormaliser.normalise(issue.status.name), tint: statusColour)
                }
                Text(issue.summary)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.foreground)
                    .lineLimit(2)
                if !issue.labels.isEmpty {
                    HStack {
                        ForEach(issue.labels.prefix(4), id: \.self) { BalmChip($0) }
                    }
                }
            }
            Spacer()
            if let assignee = issue.assignee {
                Text(initials(for: assignee.displayName))
                    .font(theme.typography.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(theme.palette.secondary))
                    .foregroundStyle(theme.palette.foreground)
            }
        }
        .padding(.vertical, theme.spacing.xs)
    }

    private var statusColour: Color {
        let token = StatusNormaliser.semanticTokenName(issue.status.name)
        let semantic: BalmPalette.Semantic
        switch token {
        case .primary: semantic = .primary
        case .destructive: semantic = .destructive
        case .chart1: semantic = .chart1
        case .chart3: semantic = .chart3
        case .chart4: semantic = .chart4
        case .chart5: semantic = .chart5
        case .neutral: semantic = .neutral
        }
        return theme.palette.color(for: semantic)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return initials.joined().uppercased()
    }
}
