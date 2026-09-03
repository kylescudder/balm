import SwiftUI
import BalmModels
import BalmDesignSystem

/// A board column is a plain stack with a glyph header, not a box. The only
/// time it draws a boundary is while a card is being dragged over it.
struct BoardColumnView: View {
    @Environment(\.balmTheme) private var theme
    @Environment(\.openIssue) private var openIssue
    let column: BoardColumn
    /// Drag-and-drop: called with the dropped issue key + this column.
    var onMove: ((String, BoardColumn) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(column.issues, id: \.self) { issue in
                        Button {
                            openIssue(issue)
                        } label: {
                            IssueCardView(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .draggable(issue.key)
                    }
                    if column.issues.isEmpty {
                        Text("Nothing here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
            }
        }
        .padding(6)
        .background(
            isTargeted ? AnyShapeStyle(theme.palette.accent.opacity(0.10)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isTargeted ? theme.palette.accent : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
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
        HStack(spacing: 8) {
            StatusGlyph(column.title, size: 14)
            Text(StatusNormaliser.normalise(column.title))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(column.issues.count, format: .number)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}
