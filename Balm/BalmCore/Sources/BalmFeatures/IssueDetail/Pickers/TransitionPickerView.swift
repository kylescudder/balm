import SwiftUI
import BalmModels
import BalmDesignSystem

struct TransitionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let transitions: [JiraTransition]
    let currentStatus: JiraStatus
    let onSelect: (JiraTransition) -> Void

    var body: some View {
        PickerScaffold(title: "Status") {
            KeyboardFilterList(
                items: transitions,
                prompt: "Filter statuses",
                emptyText: transitions.isEmpty ? "No transitions are available from here." : "No statuses match.",
                initialSelection: transitions.first { $0.to.name == currentStatus.name },
                filterText: { "\(StatusNormaliser.normalise($0.to.name)) \($0.name)" },
                onActivate: { transition in
                    onSelect(transition)
                    dismiss()
                }
            ) { transition in
                HStack(spacing: 10) {
                    StatusLabel(status: transition.to.name)
                    Spacer()
                    if transition.to.name == currentStatus.name {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
        }
    }
}
