import SwiftUI
import BalmModels
import BalmAPI

/// Raw-JQL escape hatch. The user writes the discretionary part of the query;
/// `JQLBuilder` always scopes it to the project and selected sprint(s). Shows a
/// live preview of the exact query that will run.
struct AdvancedJQLView: View {
    @Binding var jql: String
    let projectKey: String
    let sprints: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced JQL")
                .font(.headline)
            Text("Scoped automatically to this project and the selected sprint(s). Write the rest, e.g. resolution = Unresolved AND (duedate != EMPTY OR labels IN (jira_escalated)).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $jql)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            if let preview {
                Text("Resulting query")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                    )
            } else if sprints.isEmpty {
                Text("Select a sprint to preview the full query.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preview: String? {
        guard !sprints.isEmpty else { return nil }
        return JQLBuilder(projectKey: projectKey, sprints: sprints, definition: .jql(jql)).build()
    }
}
