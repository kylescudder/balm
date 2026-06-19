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
    @Environment(\.openIssue) private var openIssue
    let link: JiraIssueLink
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            Button {
                guard !isOptimistic else { return }
                openIssue(link.issue.asJiraIssue())
            } label: {
                HStack(spacing: theme.spacing.s) {
                    Text(link.issue.key)
                        .font(theme.typography.caption.monospaced())
                        .foregroundStyle(theme.palette.mutedForeground)
                    Text(link.issue.summary)
                        .font(theme.typography.body)
                        .foregroundStyle(isHovering ? theme.palette.primary : theme.palette.foreground)
                        .underline(isHovering)
                        .lineLimit(1)
                    Spacer(minLength: theme.spacing.s)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOptimistic)
            #if os(macOS)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .help("Open \(link.issue.key)")
            #endif

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

private extension JiraIssueLink.LinkedIssue {
    /// Bridge a linked-issue summary into a full `JiraIssue` for navigation.
    /// Non-optional fields fall back to placeholders; the detail view reloads
    /// from the key, so these are only the seed shown for the first frame.
    func asJiraIssue() -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: summary,
            status: status ?? JiraStatus(
                name: "",
                statusCategory: JiraStatusCategory(key: "new", colorName: "blue")
            ),
            priority: priority ?? JiraPriority(name: ""),
            issueType: issueType ?? JiraIssueType(name: "")
        )
    }
}
