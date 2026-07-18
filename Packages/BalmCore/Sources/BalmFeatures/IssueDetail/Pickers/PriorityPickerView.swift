import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct PriorityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme
    @Environment(AppEnvironment.self) private var env

    let currentName: String
    let onSelect: (JiraPriority) -> Void

    @State private var priorities: [JiraPriority] = []
    @State private var isLoading = false
    @State private var searchText = ""

    var body: some View {
        PickerScaffold(title: "Priority") {
            List {
                if isLoading {
                    ProgressView()
                } else if filteredPriorities.isEmpty {
                    ContentUnavailableView("No priorities", systemImage: "flag")
                } else {
                    ForEach(filteredPriorities, id: \.name) { priority in
                        Button {
                            onSelect(priority)
                            dismiss()
                        } label: {
                            HStack(spacing: theme.spacing.s) {
                                if let icon = priority.iconUrl {
                                    AsyncImage(url: icon) { phase in
                                        if case .success(let img) = phase {
                                            img.resizable().scaledToFit()
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: 18, height: 18)
                                }
                                Text(priority.name)
                                Spacer()
                                if priority.name == currentName {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.palette.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search priorities")
            .task { await load() }
        }
    }

    private var filteredPriorities: [JiraPriority] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return priorities }
        return priorities.filter { $0.name.localizedStandardContains(query) }
    }

    private func load() async {
        guard priorities.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            priorities = try await env.api.send(MetadataEndpoints.Priorities())
        } catch {
            env.toaster.error("Couldn't load priorities: \(error.localizedDescription)")
        }
    }
}
