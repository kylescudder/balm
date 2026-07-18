import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// Issue metadata shown with platform-native row/editing affordances.
///
/// The previous implementation wrapped every editable field in custom rounded
/// "dropdown" chrome. That looked alien on both iOS and macOS, especially when
/// the iOS detail card presented the panel inside a sheet. Keep the metadata as
/// plain labelled rows and present native picker sheets/lists for editing.
struct IssueMetadataPanel: View {
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: IssueDetailViewModel

    @State private var priorities: [JiraPriority] = []
    @State private var sprints: [JiraSprint] = []
    @State private var components: [JiraComponent] = []
    @State private var versions: [JiraVersion] = []
    @State private var editingField: EditableField?

    var body: some View {
        let issue = model.issue ?? placeholderIssue

        VStack(alignment: .leading, spacing: 0) {
            editableField("Status", field: .status) { StatusChip(status: issue.status.name) }
            editableField("Priority", field: .priority) { Text(issue.priority.name) }
            editableField("Assignee", field: .assignee) { assigneeValue(issue) }
            readonlyField("Reporter") { reporterValue(issue) }
            readonlyField("Type") { Text(issue.issueType.name) }
            editableField("Sprint", field: .sprint) { Text(issue.sprint?.name ?? "Backlog") }
            editableField("Due", field: .dueDate) { optionalText(issue.dueDate) }
            editableField("Components", field: .components) { summaryText(issue.components.map(\.name)) }
            if let name = issue.instanceName {
                readonlyField("Instance / Database") { Text(name) }
            }
            editableField("Fix Versions", field: .versions) { summaryText(issue.fixVersions.map(\.name)) }
            editableField("Labels", field: .labels) { summaryText(issue.labels) }
            readonlyField("Created") { dateText(issue.created) }
            readonlyField("Updated") { dateText(issue.updated) }
        }
        .font(theme.typography.body)
        .foregroundStyle(theme.palette.foreground)
        .task(id: issue.projectKey) { await loadOptions(projectKey: issue.projectKey) }
        .sheet(item: $editingField) { field in
            editor(for: field, issue: issue)
        }
    }

    // MARK: - Rows

    private func editableField<V: View>(
        _ title: String,
        field: EditableField,
        @ViewBuilder value: () -> V
    ) -> some View {
        Button {
            editingField = field
        } label: {
            row(title, showsDisclosure: true) {
                value()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to edit")
        .overlay(alignment: .bottom) { Divider().padding(.leading, theme.spacing.l) }
    }

    private func readonlyField<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        row(title, showsDisclosure: false) { value() }
            .overlay(alignment: .bottom) { Divider().padding(.leading, theme.spacing.l) }
    }

    private func row<V: View>(_ title: String, showsDisclosure: Bool, @ViewBuilder value: () -> V) -> some View {
        LabeledContent {
            HStack(spacing: theme.spacing.xs) {
                value()
                    .multilineTextAlignment(.trailing)
                #if os(iOS)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                #endif
            }
            .foregroundStyle(theme.palette.foreground)
        } label: {
            Text(title)
                .foregroundStyle(theme.palette.mutedForeground)
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.s)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func optionalText(_ value: String?) -> some View {
        Text(value ?? "None")
            .foregroundStyle(value == nil ? theme.palette.mutedForeground : theme.palette.foreground)
    }

    @ViewBuilder
    private func summaryText(_ items: [String]) -> some View {
        if items.isEmpty {
            Text("None").foregroundStyle(theme.palette.mutedForeground)
        } else {
            Text(items.joined(separator: ", "))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func assigneeValue(_ issue: JiraIssue) -> some View {
        if let a = issue.assignee {
            HStack(spacing: theme.spacing.xs) {
                AvatarView(name: a.displayName, avatarURL: a.avatarURL, size: 20)
                Text(a.displayName)
            }
        } else {
            Text("Unassigned").foregroundStyle(theme.palette.mutedForeground)
        }
    }

    @ViewBuilder
    private func reporterValue(_ issue: JiraIssue) -> some View {
        if let r = issue.reporter {
            HStack(spacing: theme.spacing.xs) {
                AvatarView(name: r.displayName, avatarURL: r.avatarURL, size: 20)
                Text(r.displayName)
            }
        } else {
            Text("—").foregroundStyle(theme.palette.mutedForeground)
        }
    }

    @ViewBuilder
    private func dateText(_ date: Date?) -> some View {
        Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            .foregroundStyle(date == nil ? theme.palette.mutedForeground : theme.palette.foreground)
    }

    // MARK: - Editors

    @ViewBuilder
    private func editor(for field: EditableField, issue: JiraIssue) -> some View {
        switch field {
        case .status:
            TransitionPickerView(transitions: model.transitions, currentStatus: issue.status) { transition in
                Task { await model.applyTransition(transition) }
            }
        case .priority:
            PriorityPickerView(currentName: issue.priority.name) { priority in
                Task { await model.setPriority(priority.name) }
            }
        case .assignee:
            AssigneePickerView(projectKey: issue.projectKey, currentAccountID: issue.assignee?.accountId) { user in
                Task { await model.setAssignee(user) }
            }
        case .sprint:
            SprintPickerView(projectKey: issue.projectKey, currentSprintID: issue.sprint?.id) { sprint in
                Task { await model.setSprint(sprint) }
            }
        case .dueDate:
            DueDatePickerView(currentValue: issue.dueDate) { value in
                Task { await model.setDueDate(value) }
            }
        case .components:
            NativeComponentsPickerView(
                components: components,
                currentNames: issue.components.map(\.name)
            ) { names in
                Task { await model.setComponents(names: names) }
            }
        case .versions:
            VersionsPickerView(projectKey: issue.projectKey, current: issue.fixVersions) { versions in
                Task { await model.setFixVersions(versions) }
            }
        case .labels:
            LabelsEditorView(current: issue.labels) { labels in
                Task { await model.setLabels(labels) }
            }
        case .description:
            EmptyView()
        }
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
