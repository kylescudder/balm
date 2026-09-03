import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

struct PriorityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    let currentName: String
    let onSelect: (JiraPriority) -> Void

    @State private var priorities: [JiraPriority] = []
    @State private var isLoading = false

    var body: some View {
        PickerScaffold(title: "Priority") {
            KeyboardFilterList(
                items: priorities,
                prompt: "Filter priorities",
                isLoading: isLoading,
                emptyText: "No priorities match.",
                initialSelection: priorities.first { $0.name == currentName },
                filterText: { $0.name },
                onActivate: { priority in
                    onSelect(priority)
                    dismiss()
                }
            ) { priority in
                HStack(spacing: 10) {
                    PriorityIcon(priority: priority, size: 16)
                    Text(priority.name)
                    Spacer()
                    if priority.name == currentName {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard priorities.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            priorities = try await env.api.send(MetadataEndpoints.Priorities())
        } catch {
            env.toaster.report(error, "Couldn't load priorities")
        }
    }
}
