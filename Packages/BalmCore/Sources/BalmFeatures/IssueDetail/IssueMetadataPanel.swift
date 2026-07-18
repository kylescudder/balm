import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

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

        Group {
            #if os(iOS)
            iosSections(issue)
            #else
            macInspectorRows(issue)
            #endif
        }
        .task(id: issue.projectKey) { await loadOptions(projectKey: issue.projectKey) }
        .sheet(item: $editingField) { field in
            editor(for: field, issue: issue)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func iosSections(_ issue: JiraIssue) -> some View {
        Section("Details") {
            editableRow("Status", field: .status) { Text(StatusNormaliser.normalise(issue.status.name)) }
            editableRow("Priority", field: .priority) { Text(issue.priority.name) }
            editableRow("Assignee", field: .assignee) { assigneeValue(issue) }
            readonlyRow("Reporter") { reporterValue(issue) }
            readonlyRow("Type") { Text(issue.issueType.name) }
            editableRow("Sprint", field: .sprint) { Text(issue.sprint?.name ?? "Backlog") }
            editableRow("Due", field: .dueDate) { optionalText(issue.dueDate) }
            editableRow("Components", field: .components) { summaryText(issue.components.map(\.name)) }
            editableRow("Fix Versions", field: .versions) { summaryText(issue.fixVersions.map(\.name)) }
            editableRow("Labels", field: .labels) { summaryText(issue.labels) }
            if let name = issue.instanceName {
                readonlyRow("Instance / Database") { Text(name) }
            }
        }

        Section("Dates") {
            readonlyRow("Created") { dateText(issue.created) }
            readonlyRow("Updated") { dateText(issue.updated) }
        }
    }

    private func editableRow<V: View>(_ title: String, field: EditableField, @ViewBuilder value: () -> V) -> some View {
        Button {
            editingField = field
        } label: {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    value()
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func readonlyRow<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        LabeledContent(title) {
            value()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
    #endif

    #if !os(iOS)
    private func macInspectorRows(_ issue: JiraIssue) -> some View {
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
    }

    private func editableField<V: View>(_ title: String, field: EditableField, @ViewBuilder value: () -> V) -> some View {
        Button {
            editingField = field
        } label: {
            row(title, showsDisclosure: true) { value() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Double click to edit")
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
    #endif

    @ViewBuilder
    private func optionalText(_ value: String?) -> some View {
        Text(value ?? "None")
            .foregroundStyle(value == nil ? .secondary : .primary)
    }

    @ViewBuilder
    private func summaryText(_ items: [String]) -> some View {
        if items.isEmpty {
            Text("None").foregroundStyle(.secondary)
        } else {
            Text(items.joined(separator: ", "))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func assigneeValue(_ issue: JiraIssue) -> some View {
        if let assignee = issue.assignee {
            HStack(spacing: 6) {
                AvatarView(name: assignee.displayName, avatarURL: assignee.avatarURL, size: 20)
                Text(assignee.displayName)
            }
        } else {
            Text("Unassigned").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reporterValue(_ issue: JiraIssue) -> some View {
        if let reporter = issue.reporter {
            HStack(spacing: 6) {
                AvatarView(name: reporter.displayName, avatarURL: reporter.avatarURL, size: 20)
                Text(reporter.displayName)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dateText(_ date: Date?) -> some View {
        Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            .foregroundStyle(date == nil ? .secondary : .primary)
    }

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
            AssigneePickerView(projectKey: issue.projectKey, currentAccountID: nil) { user in
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
