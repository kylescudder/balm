import SwiftUI
import BalmModels
import BalmDesignSystem

struct SprintMultiSelectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let model: IssueListViewModel
    @State private var draft: Set<String> = []

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Sprints")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            model.setSprintSelection(draft)
                            dismiss()
                        }
                        .disabled(model.availableSprints.isEmpty)
                    }
                }
                .onAppear { draft = model.selectedSprintIDs }
        }
        // macOS sheets ignore `presentationDetents`, so without an explicit
        // size the List collapses to zero height. Give the sheet real room.
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if model.availableSprints.isEmpty {
            ContentUnavailableView(
                "No sprints",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Couldn't load this board's sprints. Pull to refresh, or check you're connected.")
            )
        } else {
            List {
                ForEach(model.availableSprints, id: \.self) { sprint in
                    row(for: sprint)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for sprint: JiraSprint) -> some View {
        let key = sprint.name
        Button {
            if draft.contains(key) {
                draft.remove(key)
            } else {
                draft.insert(key)
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(sprint.name).foregroundStyle(theme.palette.foreground)
                    if !sprint.state.isEmpty {
                        Text(sprint.state.capitalized)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.mutedForeground)
                    }
                }
                Spacer()
                if draft.contains(key) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.palette.primary)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(theme.palette.border)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
