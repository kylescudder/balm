import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// Issue metadata, designed for the narrow detail inspector: each field stacks
/// a small caps label above a full-width control so values never truncate.
/// Single-select fields use native `Menu`s (options preloaded); assignee, due
/// date and labels use native sheets — assignee via a sheet specifically so its
/// avatar renders correctly (SwiftUI's Menu label mangles `AsyncImage`).
struct IssueMetadataPanel: View {
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: IssueDetailViewModel

    @State private var priorities: [JiraPriority] = []
    @State private var sprints: [JiraSprint] = []
    @State private var components: [JiraComponent] = []
    @State private var versions: [JiraVersion] = []

    @State private var editingAssignee = false
    @State private var editingDueDate = false
    @State private var editingLabels = false

    var body: some View {
        let issue = model.issue ?? placeholderIssue

        VStack(spacing: 0) {
            statusField(issue)
            priorityField(issue)
            assigneeField(issue)
            readonlyField("Reporter") { reporterValue(issue) }
            readonlyField("Type") { Text(issue.issueType.name).foregroundStyle(theme.palette.foreground) }
            sprintField(issue)
            dueField(issue)
            componentsField(issue)
            if let name = issue.instanceName {
                readonlyField("Instance / Database") {
                    Text(name).foregroundStyle(theme.palette.foreground)
                }
            }
            versionsField(issue)
            labelsField(issue)
            readonlyField("Created") { dateText(issue.created) }
            readonlyField("Updated") { dateText(issue.updated) }
        }
        .padding(.vertical, theme.spacing.s)
        .background(theme.palette.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).strokeBorder(theme.palette.border))
        .task(id: issue.projectKey) { await loadOptions(projectKey: issue.projectKey) }
        .sheet(isPresented: $editingAssignee) {
            AssigneePickerView(projectKey: issue.projectKey, currentAccountID: nil) { user in
                Task { await model.setAssignee(user) }
            }
        }
        .sheet(isPresented: $editingDueDate) {
            DueDatePickerView(currentValue: issue.dueDate) { value in
                Task { await model.setDueDate(value) }
            }
        }
        .sheet(isPresented: $editingLabels) {
            LabelsEditorView(current: issue.labels) { labels in
                Task { await model.setLabels(labels) }
            }
        }
    }

    // MARK: - Fields

    private func statusField(_ issue: JiraIssue) -> some View {
        menuField("Status") {
            ForEach(model.transitions, id: \.id) { t in
                Button(StatusNormaliser.normalise(t.to.name)) {
                    Task { await model.applyTransition(t) }
                }
            }
        } value: {
            StatusChip(status: issue.status.name)
        }
    }

    private func priorityField(_ issue: JiraIssue) -> some View {
        menuField("Priority") {
            ForEach(priorities, id: \.name) { p in
                Button { Task { await model.setPriority(p.name) } } label: {
                    if p.name == issue.priority.name { Label(p.name, systemImage: "checkmark") }
                    else { Text(p.name) }
                }
            }
        } value: {
            Text(issue.priority.name).foregroundStyle(theme.palette.foreground)
        }
    }

    private func assigneeField(_ issue: JiraIssue) -> some View {
        field("Assignee") {
            Button { editingAssignee = true } label: {
                chrome {
                    if let a = issue.assignee {
                        AvatarView(name: a.displayName, avatarURL: a.avatarURL, size: 20)
                        Text(a.displayName).foregroundStyle(theme.palette.foreground)
                    } else {
                        Text("Unassigned").foregroundStyle(theme.palette.mutedForeground)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func sprintField(_ issue: JiraIssue) -> some View {
        menuField("Sprint") {
            Button("Backlog") { Task { await model.setSprint(nil) } }
            ForEach(sprints, id: \.id) { s in
                Button { Task { await model.setSprint(s) } } label: {
                    if s.id == issue.sprint?.id { Label(s.name, systemImage: "checkmark") }
                    else { Text(s.name) }
                }
            }
        } value: {
            Text(issue.sprint?.name ?? "Backlog").foregroundStyle(theme.palette.foreground)
        }
    }

    private func dueField(_ issue: JiraIssue) -> some View {
        field("Due") {
            Button { editingDueDate = true } label: {
                chrome {
                    Text(issue.dueDate ?? "None")
                        .foregroundStyle(issue.dueDate == nil ? theme.palette.mutedForeground : theme.palette.foreground)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func componentsField(_ issue: JiraIssue) -> some View {
        let selected = Set(issue.components.map(\.name))
        return menuField("Components") {
            if components.isEmpty { Text("No components") }
            ForEach(components, id: \.name) { c in
                Button { toggleComponent(c, in: issue) } label: {
                    if selected.contains(c.name) { Label(c.name, systemImage: "checkmark") }
                    else { Text(c.name) }
                }
            }
        } value: {
            summaryText(issue.components.map(\.name))
        }
    }

    private func versionsField(_ issue: JiraIssue) -> some View {
        let selectedIDs = Set(issue.fixVersions.map(\.id))
        return menuField("Fix Versions") {
            if versions.isEmpty { Text("No versions") }
            ForEach(versions, id: \.id) { v in
                Button { toggleVersion(v, in: issue) } label: {
                    if selectedIDs.contains(v.id) { Label(v.name, systemImage: "checkmark") }
                    else { Text(v.name) }
                }
            }
        } value: {
            summaryText(issue.fixVersions.map(\.name))
        }
    }

    private func labelsField(_ issue: JiraIssue) -> some View {
        field("Labels") {
            Button { editingLabels = true } label: {
                chrome { summaryText(issue.labels) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Building blocks

    /// A field: caps label stacked above a full-width control.
    private func field<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(theme.palette.mutedForeground)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.s)
    }

    /// Read-only field — value sits directly under the label, no control chrome.
    private func readonlyField<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        field(title) {
            HStack(spacing: theme.spacing.xs) { value() }
                .font(theme.typography.body)
        }
    }

    /// Editable field backed by a native menu.
    private func menuField<M: View, V: View>(
        _ title: String,
        @ViewBuilder menu: () -> M,
        @ViewBuilder value: () -> V
    ) -> some View {
        field(title) {
            Menu {
                menu()
            } label: {
                chrome { value() }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    /// The pill chrome that makes a Menu/Button read as a full-width dropdown:
    /// value on the left, disclosure chevron on the right.
    private func chrome<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: theme.spacing.xs) {
            content()
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(theme.palette.mutedForeground)
        }
        .font(theme.typography.body)
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.palette.secondary.opacity(0.45),
            in: RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func summaryText(_ items: [String]) -> some View {
        if items.isEmpty {
            Text("None").foregroundStyle(theme.palette.mutedForeground)
        } else {
            Text(items.joined(separator: ", "))
                .foregroundStyle(theme.palette.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func reporterValue(_ issue: JiraIssue) -> some View {
        if let r = issue.reporter {
            AvatarView(name: r.displayName, avatarURL: r.avatarURL, size: 20)
            Text(r.displayName).foregroundStyle(theme.palette.foreground)
        } else {
            Text("—").foregroundStyle(theme.palette.mutedForeground)
        }
    }

    @ViewBuilder
    private func dateText(_ date: Date?) -> some View {
        Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            .foregroundStyle(date == nil ? theme.palette.mutedForeground : theme.palette.foreground)
    }

    // MARK: - Mutations

    private func toggleComponent(_ component: JiraComponent, in issue: JiraIssue) {
        var names = Set(issue.components.map(\.name))
        if names.contains(component.name) { names.remove(component.name) } else { names.insert(component.name) }
        Task { await model.setComponents(names: names.sorted()) }
    }

    private func toggleVersion(_ version: JiraVersion, in issue: JiraIssue) {
        var ids = Set(issue.fixVersions.map(\.id))
        if ids.contains(version.id) { ids.remove(version.id) } else { ids.insert(version.id) }
        Task { await model.setFixVersions(versions.filter { ids.contains($0.id) }) }
    }

    // MARK: - Option loading

    private func loadOptions(projectKey: String) async {
        guard !projectKey.isEmpty, projectKey != "—" else { return }
        if let p = try? await env.api.send(MetadataEndpoints.Priorities()) { priorities = p }
        if let c = try? await env.api.send(ProjectEndpoints.Components(projectKeyOrId: projectKey)) { components = c }
        if let v = try? await env.api.send(ProjectEndpoints.Versions(projectKeyOrId: projectKey)) { versions = v }
        if let boards = try? await env.api.send(ProjectEndpoints.Boards(projectKeyOrId: projectKey)),
           let board = boards.values.first,
           let resp = try? await env.api.send(ProjectEndpoints.Sprints(boardID: board.id, states: ["active", "future"])) {
            sprints = resp.values
        }
    }

    private var placeholderIssue: JiraIssue {
        JiraIssue(
            id: "0",
            key: "—",
            summary: "Loading…",
            status: JiraStatus(name: "—", statusCategory: JiraStatusCategory(key: "new", colorName: "blue")),
            priority: JiraPriority(name: "—"),
            issueType: JiraIssueType(name: "—")
        )
    }
}

/// Tiny wrap-around stack for chips. Uses `Layout` so it works on macOS 15 / iOS 18.
struct FlexibleStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing) { content() }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if rowWidth + s.width > width && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxWidth = max(maxWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        totalHeight += rowHeight
        maxWidth = max(maxWidth, rowWidth)
        return CGSize(width: min(maxWidth, width), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let width = bounds.width

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + width && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
