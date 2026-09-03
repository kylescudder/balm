import SwiftUI
import Observation
import BalmModels
import BalmAPI
import BalmDesignSystem

public struct NewIssueView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.balmTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let project: JiraProject
    private let onCreated: (IssueEndpoints.Create.CreateResponse) -> Void

    @State private var summary: String = ""
    @State private var descriptionText: String = ""
    @State private var issueType: JiraIssueType?
    @State private var assignee: JiraUser?
    @State private var priority: JiraPriority?
    @State private var sprint: JiraSprint?
    @State private var componentFieldID: String?
    @State private var componentFieldName = "Components"
    @State private var componentRequired = false
    @State private var componentMultiple = false
    @State private var componentOptions: [ComponentOption] = []
    @State private var selectedComponents: [ComponentOption] = []
    @State private var fixVersions: [JiraVersion] = []
    @State private var labels: [String] = []
    @State private var dueDate: String?

    @State private var availableIssueTypes: [JiraIssueType] = []
    @State private var isSubmitting = false
    @State private var activePicker: PickerKind?

    enum PickerKind: String, Identifiable {
        case issueType, assignee, priority, sprint, components, versions, labels, dueDate
        var id: String { rawValue }
    }

    public init(
        project: JiraProject,
        defaultSprint: JiraSprint? = nil,
        onCreated: @escaping (IssueEndpoints.Create.CreateResponse) -> Void = { _ in }
    ) {
        self.project = project
        self.onCreated = onCreated
        self._sprint = State(initialValue: defaultSprint)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                        .labelsHidden()
                }

                Section("Type") {
                    picker("Issue type", value: issueType?.name) {
                        activePicker = .issueType
                    }
                }

                Section("Description") {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(5...10)
                        .labelsHidden()
                }

                Section("Assignment") {
                    picker("Assignee", value: assignee?.displayName ?? "Unassigned") {
                        activePicker = .assignee
                    }
                    picker("Priority", value: priority?.name) {
                        activePicker = .priority
                    }
                    picker("Sprint", value: sprint?.name ?? "Backlog") {
                        activePicker = .sprint
                    }
                }

                Section("Categorisation") {
                    if componentFieldID != nil {
                        picker(
                            componentFieldName,
                            value: selectedComponents.isEmpty
                                ? nil
                                : selectedComponents.map(\.label).joined(separator: ", ")
                        ) {
                            activePicker = .components
                        }
                    }
                    picker("Fix Versions", value: fixVersions.isEmpty ? nil : fixVersions.map(\.name).joined(separator: ", ")) {
                        activePicker = .versions
                    }
                    picker("Labels", value: labels.isEmpty ? nil : labels.joined(separator: ", ")) {
                        activePicker = .labels
                    }
                    picker("Due date", value: dueDate) {
                        activePicker = .dueDate
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Issue in \(project.key)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Create", action: submit)
                            .disabled(!canSubmit)
                    }
                }
            }
            .sheet(item: $activePicker) { kind in
                pickerSheet(kind)
            }
            .task { await loadIssueTypes() }
            .task(id: issueType?.id) { await loadComponentField() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
    }

    private var canSubmit: Bool {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              issueType != nil,
              !isSubmitting else { return false }
        // Honour a required component field — Jira would reject the create otherwise.
        if componentRequired && componentFieldID != nil && selectedComponents.isEmpty { return false }
        return true
    }

    @ViewBuilder
    private func picker(_ title: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent(title) {
                HStack(spacing: theme.spacing.xs) {
                    Text(value ?? "Pick…")
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickerSheet(_ kind: PickerKind) -> some View {
        switch kind {
        case .issueType:
            IssueTypePickerView(
                available: availableIssueTypes,
                currentID: issueType?.id,
                onSelect: { issueType = $0 }
            )
        case .assignee:
            AssigneePickerView(
                projectKey: project.key,
                currentDisplayName: assignee?.displayName,
                onSelect: { assignee = $0 }
            )
        case .priority:
            PriorityPickerView(
                currentName: priority?.name ?? "",
                onSelect: { priority = $0 }
            )
        case .sprint:
            SprintPickerView(
                projectKey: project.key,
                currentSprintID: sprint?.id,
                onSelect: { sprint = $0 }
            )
        case .components:
            ComponentsPickerView(
                title: componentFieldName,
                options: componentOptions,
                allowsMultiple: componentMultiple,
                current: selectedComponents,
                onApply: { selectedComponents = $0 }
            )
        case .versions:
            VersionsPickerView(
                projectKey: project.key,
                current: fixVersions,
                onApply: { fixVersions = $0 }
            )
        case .labels:
            LabelsEditorView(
                current: labels,
                onApply: { labels = $0 }
            )
        case .dueDate:
            DueDatePickerView(
                currentValue: dueDate,
                onApply: { dueDate = $0 }
            )
        }
    }

    private func loadIssueTypes() async {
        guard availableIssueTypes.isEmpty else { return }
        do {
            availableIssueTypes = try await env.api.send(
                MetadataEndpoints.ProjectIssueTypes(projectID: project.id)
            ).filter { $0.subtask != true }
            if issueType == nil { issueType = availableIssueTypes.first }
        } catch {
            env.toaster.report(error, "Couldn't load issue types")
        }
    }

    /// Resolve the project's component field from the selected issue type's
    /// create metadata. Team-managed projects have no system `components` field —
    /// "Component" is a custom select — so options must come from createmeta
    /// rather than the (empty) `/project/{key}/components` endpoint.
    private func loadComponentField() async {
        guard let typeID = issueType?.id else {
            componentFieldID = nil; componentOptions = []
            return
        }
        do {
            let resp = try await env.api.send(
                MetadataEndpoints.CreateMetaFields(projectIdOrKey: project.key, issueTypeId: typeID)
            )
            guard let field = MetadataEndpoints.CreateMetaFields.componentField(from: resp.fields),
                  let fieldID = field.identifier else {
                componentFieldID = nil; componentOptions = []; selectedComponents = []
                return
            }
            componentFieldID = fieldID
            componentFieldName = field.name ?? "Components"
            componentRequired = field.required ?? false
            componentMultiple = field.isMultiValue
            componentOptions = (field.allowedValues ?? []).compactMap { value in
                guard let id = value.id, let label = value.label, !label.isEmpty else { return nil }
                return ComponentOption(id: id, label: label)
            }
            // Drop any prior selection that isn't valid for the resolved field.
            let valid = Set(componentOptions.map(\.id))
            selectedComponents = selectedComponents.filter { valid.contains($0.id) }
        } catch {
            env.toaster.report(error, "Couldn't load fields")
        }
    }

    private func submit() {
        guard canSubmit, let issueType else { return }
        isSubmitting = true
        let issueTypeID = issueType.id ?? ""
        let assigneeID = assignee?.accountId
        let priorityName = priority?.name
        let sprintRef = sprint
        let summaryValue = summary
        let descValue = descriptionText
        let componentFieldIDValue = componentFieldID
        let componentMultipleValue = componentMultiple
        let selectedComponentIDs = selectedComponents.map(\.id)
        let versionsValue = fixVersions
        let labelsValue = labels
        let dueDateValue = dueDate
        let projectKey = project.key

        Task {
            var fields: [String: AnyJSON] = Dictionary(uniqueKeysWithValues: [
                IssueFieldPatch.projectByKey(projectKey),
                IssueFieldPatch.summary(summaryValue),
                IssueFieldPatch.issueType(id: issueTypeID)
            ])

            if !descValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let (k, v) = IssueFieldPatch.description(plainText: descValue)
                fields[k] = v
            }
            if let assigneeID {
                let (k, v) = IssueFieldPatch.assignee(accountID: assigneeID)
                fields[k] = v
            }
            if let priorityName {
                let (k, v) = IssueFieldPatch.priority(name: priorityName)
                fields[k] = v
            }
            if let componentFieldIDValue, !selectedComponentIDs.isEmpty {
                let (k, v) = IssueFieldPatch.optionField(
                    componentFieldIDValue,
                    optionIDs: selectedComponentIDs,
                    multiple: componentMultipleValue
                )
                fields[k] = v
            }
            if !versionsValue.isEmpty {
                let (k, v) = IssueFieldPatch.fixVersions(ids: versionsValue.map(\.id))
                fields[k] = v
            }
            if !labelsValue.isEmpty {
                let (k, v) = IssueFieldPatch.labels(labelsValue)
                fields[k] = v
            }
            if let dueDateValue {
                let (k, v) = IssueFieldPatch.dueDate(dueDateValue)
                fields[k] = v
            }

            do {
                let response = try await env.api.send(IssueEndpoints.Create(fields: fields))
                // If a sprint was chosen, move the new issue via the agile API.
                if let sprintRef, let id = Int(sprintRef.id) {
                    try? await env.api.sendVoid(
                        IssueEndpoints.AddToSprint(sprintID: id, issueKeys: [response.key])
                    )
                }
                // Success feedback (toast + refresh) is the presenting view's
                // job — it owns the list and navigation the toast acts on.
                onCreated(response)
                dismiss()
            } catch {
                env.toaster.report(error, "Create failed")
            }
            isSubmitting = false
        }
    }
}

struct IssueTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let available: [JiraIssueType]
    let currentID: String?
    let onSelect: (JiraIssueType) -> Void

    var body: some View {
        PickerScaffold(title: "Issue Type") {
            KeyboardFilterList(
                items: available,
                prompt: "Filter types",
                initialSelection: available.first { $0.id == currentID },
                filterText: { $0.name },
                onActivate: { onSelect($0); dismiss() }
            ) { type in
                HStack(spacing: theme.spacing.s) {
                    if let icon = type.iconUrl {
                        AsyncImage(url: icon) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFit()
                            } else { Color.clear }
                        }
                        .frame(width: 18, height: 18)
                    }
                    Text(type.name)
                    Spacer()
                    if type.id == currentID {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
        }
    }
}
