import SwiftUI
import BalmModels
import BalmDesignSystem

struct IssueLinkListView: View {
    @Bindable var model: IssueDetailViewModel

    @State private var showingAddSheet = false
    @State private var pendingDelete: JiraIssueLink?

    var body: some View {
        Group {
            #if os(iOS)
            Section {
                if model.details.issueLinks.isEmpty {
                    Text("No linked issues.")
                        .foregroundStyle(.secondary)
                }
                ForEach(grouped, id: \.0) { relationship, items in
                    ForEach(items) { link in
                        LinkRow(link: link, relationship: relationship, onDelete: { pendingDelete = link })
                    }
                }
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Link an issue", systemImage: "link.badge.plus")
                }
            } header: {
                Text("Linked issues")
            }
            #else
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading("Linked issues", count: model.details.issueLinks.count) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Link", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
                if model.details.issueLinks.isEmpty {
                    Text("No linked issues.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(grouped, id: \.0) { relationship, items in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(relationship.prefix(1).capitalized + relationship.dropFirst())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(items) { link in
                                LinkRow(link: link, relationship: relationship, onDelete: { pendingDelete = link })
                            }
                        }
                    }
                }
            }
            #endif
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

    private var grouped: [(String, [JiraIssueLink])] {
        let dict = Dictionary(grouping: model.details.issueLinks, by: \.relationship)
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }
}

private struct LinkRow: View {
    @Environment(\.openIssue) private var openIssue
    let link: JiraIssueLink
    let relationship: String
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard !isOptimistic else { return }
                openIssue(link.issue.asJiraIssue())
            } label: {
                HStack(spacing: 8) {
                    if let status = link.issue.status?.name {
                        StatusGlyph(status, size: 12)
                    }
                    Text(link.issue.key)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(link.issue.summary)
                        .underline(isHovering)
                        .lineLimit(1)
                    Spacer(minLength: 8)
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

            if !isOptimistic {
                Menu {
                    Button("Remove link", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 3)
        .opacity(isOptimistic ? 0.7 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(relationship) \(link.issue.key), \(link.issue.summary)")
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
