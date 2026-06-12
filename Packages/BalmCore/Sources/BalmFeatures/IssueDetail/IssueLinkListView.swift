import SwiftUI
import BalmModels
import BalmDesignSystem

struct IssueLinkListView: View {
    @Environment(\.balmTheme) private var theme
    @Bindable var model: IssueDetailViewModel

    @State private var showingAddSheet = false
    @State private var pendingDelete: JiraIssueLink?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            header
            if model.details.issueLinks.isEmpty {
                Text("No linked issues.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.palette.mutedForeground)
            } else {
                ForEach(grouped, id: \.0) { (relationship, items) in
                    Text(relationship.uppercased())
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.palette.mutedForeground)
                        .tracking(0.5)
                    VStack(spacing: theme.spacing.xs) {
                        ForEach(items) { link in
                            LinkRow(
                                link: link,
                                onDelete: { pendingDelete = link }
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLinkSheet(projectKey: model.issue?.projectKey ?? "") { type, direction, target in
                Task { await model.addLink(type: type, direction: direction, target: target) }
            }
        }
        .confirmationDialog(
            "Remove this link?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { link in
            Button("Remove", role: .destructive) {
                Task { await model.removeLink(id: link.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { link in
            Text("\(link.relationship) \(link.issue.key)")
        }
    }

    private var header: some View {
        HStack {
            SectionHeading("Linked Issues (\(model.details.issueLinks.count))")
            Spacer()
            Button {
                showingAddSheet = true
            } label: {
                Label("Link Issue", systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private var grouped: [(String, [JiraIssueLink])] {
        let dict = Dictionary(grouping: model.details.issueLinks, by: \.relationship)
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }
}

private struct LinkRow: View {
    @Environment(\.balmTheme) private var theme
    let link: JiraIssueLink
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            Text(link.issue.key)
                .font(theme.typography.caption.monospaced())
                .foregroundStyle(theme.palette.mutedForeground)
            Text(link.issue.summary)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.foreground)
                .lineLimit(1)
            Spacer()
            if let status = link.issue.status?.name {
                StatusChip(status: status)
            }
            if !isOptimistic {
                Menu {
                    Button("Remove Link", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(theme.palette.mutedForeground)
                        .padding(.horizontal, theme.spacing.xs)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(theme.spacing.s)
        .background(theme.palette.secondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.sm))
        .opacity(isOptimistic ? 0.7 : 1.0)
    }

    private var isOptimistic: Bool { link.id.hasPrefix("tmp-link-") }
}
