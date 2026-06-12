import SwiftUI
import BalmModels
import BalmDesignSystem

struct TransitionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme
    let transitions: [JiraTransition]
    let currentStatus: JiraStatus
    let onSelect: (JiraTransition) -> Void

    var body: some View {
        PickerScaffold(title: "Move to") {
            List {
                if transitions.isEmpty {
                    Text("No transitions available.")
                        .foregroundStyle(theme.palette.mutedForeground)
                } else {
                    ForEach(transitions) { transition in
                        Button {
                            onSelect(transition)
                            dismiss()
                        } label: {
                            HStack {
                                StatusChip(status: transition.to.name)
                                Spacer()
                                if transition.to.name == currentStatus.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.palette.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
