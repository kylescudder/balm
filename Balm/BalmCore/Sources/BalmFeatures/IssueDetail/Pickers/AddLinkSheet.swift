import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct AddLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    let projectKey: String
    let onAdd: (JiraIssueLink.LinkType, JiraIssueLink.Direction, JiraIssueLink.LinkedIssue) -> Void

    @State private var linkTypes: [JiraIssueLink.LinkType] = []
    @State private var directionalOptions: [DirectionalLink] = []
    @State private var selected: DirectionalLink?

    @State private var query = ""
    @State private var suggestions: [Suggestion] = []
    @State private var picked: Suggestion?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    /// One row in the type list — "blocks" and "is blocked by" each become their own entry.
    struct DirectionalLink: Identifiable, Hashable, Sendable {
        let id: String  // typeName + direction
        let type: JiraIssueLink.LinkType
        let direction: JiraIssueLink.Direction
        var phrase: String {
            direction == .outward ? type.outward : type.inward
        }
    }

    struct Suggestion: Identifiable, Hashable, Sendable {
        let id: String  // issue key
        let key: String
        let summary: String
        let imgURL: URL?
    }

    var body: some View {
        PickerScaffold(
            title: "Link Issue",
            confirmTitle: "Add",
            canConfirm: selected != nil && picked != nil,
            onConfirm: {
                guard let selected, let picked else { return }
                onAdd(
                    selected.type,
                    selected.direction,
                    JiraIssueLink.LinkedIssue(key: picked.key, summary: picked.summary)
                )
            }
        ) {
            Form {
                Section("Relationship") {
                    if directionalOptions.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading types…").foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Type", selection: $selected) {
                            Text("Pick a relationship").tag(DirectionalLink?.none)
                            ForEach(directionalOptions) { option in
                                Text(option.phrase.capitalized).tag(Optional(option))
                            }
                        }
                    }
                }

                Section("Target Issue") {
                    TextField("Search by key or summary", text: $query)
                        .onChange(of: query) { _, value in scheduleSearch(value) }

                    if let picked {
                        LabeledContent {
                            Button("Clear") { self.picked = nil }
                        } label: {
                            suggestionLabel(key: picked.key, summary: picked.summary)
                        }
                    } else if isSearching {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    } else if suggestions.isEmpty && !query.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestions) { suggestion in
                            Button {
                                picked = suggestion
                            } label: {
                                suggestionLabel(key: suggestion.key, summary: suggestion.summary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .task { await loadLinkTypes() }
        }
    }

    private func suggestionLabel(key: String, summary: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(summary)
                .lineLimit(1)
        }
    }

    private func loadLinkTypes() async {
        guard linkTypes.isEmpty else { return }
        do {
            let response = try await env.api.send(MetadataEndpoints.IssueLinkTypes())
            linkTypes = response.issueLinkTypes
            directionalOptions = response.issueLinkTypes.flatMap { type in
                [
                    DirectionalLink(id: "\(type.name)-out", type: type, direction: .outward),
                    DirectionalLink(id: "\(type.name)-in", type: type, direction: .inward)
                ]
            }
        } catch {
            env.toaster.report(error, "Couldn't load link types")
        }
    }

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            await runSearch(trimmed)
        }
    }

    private func runSearch(_ q: String) async {
        do {
            let response = try await env.api.send(IssueEndpoints.PickerSuggest(query: q))
            let flat = response.sections
                .compactMap(\.issues)
                .flatMap { $0 }
                .map { issue in
                    Suggestion(
                        id: issue.key,
                        key: issue.key,
                        summary: issue.summaryText ?? issue.key,
                        imgURL: issue.img.flatMap(URL.init)
                    )
                }
            // Dedupe by key while preserving order.
            var seen = Set<String>()
            suggestions = flat.filter { seen.insert($0.key).inserted }
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            isSearching = false
        }
    }
}
