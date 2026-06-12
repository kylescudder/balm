import SwiftUI
import BalmModels
import BalmDesignSystem

struct BoardColumnView: View {
    @Environment(\.balmTheme) private var theme
    let column: BoardColumn
    @Binding var selection: JiraIssue?
    /// Drag-and-drop: called with the dropped issue key + this column.
    var onMove: ((String, BoardColumn) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: theme.spacing.s) {
                    ForEach(column.issues, id: \.self) { issue in
                        NavigationLink(value: issue) {
                            IssueCardView(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { selection = issue })
                        .draggable(issue.key)
                    }
                    if column.issues.isEmpty {
                        Text("No issues")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(theme.spacing.l)
                    }
                }
                .padding(.horizontal, theme.spacing.s)
                .padding(.vertical, theme.spacing.s)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.lg)
                .strokeBorder(isTargeted ? theme.palette.primary : theme.palette.border,
                              lineWidth: isTargeted ? 2 : 1)
        )
        .dropDestination(for: String.self) { keys, _ in
            guard let key = keys.first, let onMove else { return false }
            onMove(key, column)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var header: some View {
        let token = StatusNormaliser.semanticTokenName(column.title)
        let semantic = BalmPalette.Semantic.from(token)
        let colour = theme.palette.color(for: semantic)
        return HStack(spacing: theme.spacing.s) {
            Circle()
                .fill(colour)
                .frame(width: 8, height: 8)
            Text(column.title)
                .font(theme.typography.headline)
                .foregroundStyle(theme.palette.foreground)
                .lineLimit(1)
            Spacer()
            Text("\(column.issues.count)")
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(colour)
                .padding(.horizontal, theme.spacing.s)
                .padding(.vertical, theme.spacing.xs)
                .background(colour.opacity(0.14))
                .clipShape(Capsule())
        }
        .padding(theme.spacing.m)
        .background(theme.palette.card.opacity(0.6))
    }
}
