import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// The issue's fields. Status, priority and assignee are the three people
/// change most, so they sit under the title as a strip of small buttons. The
/// rest is a two-column grid on the Mac and a grouped Details section on iOS,
/// in the same order on both. Which picker is open lives in the detail view's
/// `editingField`, so the keyboard shortcuts and the buttons open the same
/// sheet.
struct IssueMetadataPanel: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: IssueDetailViewModel
    @Binding var editingField: EditableField?

    @State private var components: [JiraComponent] = []

    var body: some View {
        let issue = model.issue ?? placeholderIssue

        Group {
            #if os(iOS)
            iosDetails(issue)
            #else
            VStack(alignment: .leading, spacing: 16) {
                IssueQuickProperties(model: model, editingField: $editingField)
                grid(issue)
            }
            #endif
        }
        .task(id: issue.projectKey) { await loadOptions(projectKey: issue.projectKey) }
        .sheet(item: $editingField) { field in
            editor(for: field, issue: issue)
        }
    }

    // MARK: - macOS grid

    #if !os(iOS)
    private func grid(_ issue: JiraIssue) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            editableRow("Sprint", field: .sprint) { Text(issue.sprint?.name ?? "Backlog") }
            editableRow("Due", field: .dueDate, key: "D") { optionalText(dueDateText(issue.dueDate)) }
            editableRow("Labels", field: .labels, key: "L") { tags(issue.labels) }
            editableRow("Components", field: .components, key: "M") { summaryText(issue.components.map(\.name)) }
            editableRow("Fix version", field: .versions, key: "V") { summaryText(issue.fixVersions.map(\.name)) }
            readonlyRow("Reporter") { reporterValue(issue) }
            readonlyRow("Type") { Text(issue.issueType.name) }
            if let name = issue.instanceName {
                readonlyRow("Instance") { Text(name) }
            }
            readonlyRow("Created") { datesText(issue) }
        }
        .font(.callout)
    }

    private func editableRow<V: View>(
        _ title: String,
        field: EditableField,
        key: String? = nil,
        @ViewBuilder value: () -> V
    ) -> some View {
        Button {
            editingField = field
        } label: {
            row(title) { value() }
        }
        .buttonStyle(.plain)
        .help(key.map { "Edit \(title.lowercased()) (\($0))" } ?? "Edit \(title.lowercased())")
        .accessibilityLabel(title)
        .accessibilityHint("Opens the \(title.lowercased()) picker")
    }

    private func readonlyRow<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        row(title) { value() }
    }

    private func row<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            value()
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
    #endif

    // MARK: - iOS details

    #if os(iOS)
    @ViewBuilder
    private func iosDetails(_ issue: JiraIssue) -> some View {
        Section("Details") {
            editableCell("Sprint", field: .sprint) { Text(issue.sprint?.name ?? "Backlog") }
            editableCell("Due", field: .dueDate) { optionalText(dueDateText(issue.dueDate)) }
            editableCell("Labels", field: .labels) { tags(issue.labels) }
            editableCell("Components", field: .components) { summaryText(issue.components.map(\.name)) }
            editableCell("Fix version", field: .versions) { summaryText(issue.fixVersions.map(\.name)) }
            LabeledContent("Reporter") { reporterValue(issue) }
            LabeledContent("Type") { Text(issue.issueType.name) }
            if let name = issue.instanceName {
                LabeledContent("Instance") { Text(name) }
            }
            LabeledContent("Created") { datesText(issue) }
        }
    }

    private func editableCell<V: View>(_ title: String, field: EditableField, @ViewBuilder value: () -> V) -> some View {
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
    #endif

    // MARK: - Values

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
        }
    }

    @ViewBuilder
    private func tags(_ labels: [String]) -> some View {
        if labels.isEmpty {
            Text("None").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(labels.prefix(4), id: \.self) { LabelTag(text: $0) }
                if labels.count > 4 {
                    Text("+\(labels.count - 4)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func reporterValue(_ issue: JiraIssue) -> some View {
        if let reporter = issue.reporter {
            HStack(spacing: 6) {
                AvatarView(name: reporter.displayName, avatarURL: reporter.avatarURL, size: 16)
                Text(reporter.displayName)
            }
        } else {
            Text("None").foregroundStyle(.secondary)
        }
    }

    /// "3 Sep, updated 2 hours ago" in one line, secondary.
    @ViewBuilder
    private func datesText(_ issue: JiraIssue) -> some View {
        if let created = issue.created {
            let createdText = created.formatted(date: .abbreviated, time: .omitted)
            if let updated = issue.updated {
                let formatter = RelativeDateTimeFormatter()
                Text("\(createdText), updated \(formatter.localizedString(for: updated, relativeTo: Date()))")
                    .foregroundStyle(.secondary)
            } else {
                Text(createdText).foregroundStyle(.secondary)
            }
        } else {
            Text("None").foregroundStyle(.secondary)
        }
    }

    private func dueDateText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .omitted)
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
            AssigneePickerView(projectKey: issue.projectKey, currentDisplayName: issue.assignee?.displayName) { user in
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
        if let c = try? await env.api.send(ProjectEndpoints.Components(projectKeyOrId: projectKey)) { components = c }
    }

    private var placeholderIssue: JiraIssue {
        JiraIssue(
            id: "0",
            key: "—",
            summary: "Loading",
            status: JiraStatus(name: "—", statusCategory: JiraStatusCategory(key: "new", colorName: "blue")),
            priority: JiraPriority(name: "—"),
            issueType: JiraIssueType(name: "—")
        )
    }
}

/// Status, priority and assignee as a strip of small buttons under the title.
/// Each opens the same keyboard-first picker its shortcut does.
struct IssueQuickProperties: View {
    @Bindable var model: IssueDetailViewModel
    @Binding var editingField: EditableField?

    var body: some View {
        let issue = model.issue ?? placeholder
        HStack(spacing: 8) {
            Button {
                editingField = .status
            } label: {
                HStack(spacing: 6) {
                    StatusLabel(status: issue.status.name, size: 13)
                    chevron
                }
            }
            .help("Change status (S)")

            Button {
                editingField = .priority
            } label: {
                HStack(spacing: 6) {
                    PriorityIcon(priority: issue.priority, size: 12)
                    Text(issue.priority.name.isEmpty ? "Priority" : issue.priority.name)
                        .lineLimit(1)
                    chevron
                }
            }
            .help("Change priority (P)")

            Button {
                editingField = .assignee
            } label: {
                HStack(spacing: 6) {
                    if let assignee = issue.assignee {
                        AvatarView(name: assignee.displayName, avatarURL: assignee.avatarURL, size: 16)
                        Text(assignee.displayName)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "person.crop.circle.dashed")
                            .foregroundStyle(.secondary)
                        Text("Unassigned")
                            .lineLimit(1)
                    }
                    chevron
                }
            }
            .help("Change assignee (A)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.callout)
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private var placeholder: JiraIssue {
        JiraIssue(
            id: "0",
            key: "—",
            summary: "Loading",
            status: JiraStatus(name: "—", statusCategory: JiraStatusCategory(key: "new", colorName: "blue")),
            priority: JiraPriority(name: "—"),
            issueType: JiraIssueType(name: "—")
        )
    }
}
