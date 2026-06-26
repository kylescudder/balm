import SwiftUI
import BalmModels
import BalmAPI
import BalmDesignSystem

/// One selectable option for the create modal's component field, addressed by
/// the Jira option `id` (submitted) with a human `label` (displayed/filtered).
struct ComponentOption: Hashable, Identifiable {
    let id: String
    let label: String
}

/// Keyboard-filterable picker for the New Issue "Component" field. Options are
/// supplied by the caller from create metadata, so it works for both the
/// standard `components` field and tenant custom selects (e.g.
/// `customfield_10312`). Single-select fields select-and-dismiss; multi-select
/// fields toggle membership and confirm with Apply.
struct ComponentsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let title: String
    let options: [ComponentOption]
    let allowsMultiple: Bool
    let onApply: ([ComponentOption]) -> Void

    @State private var draft: Set<String>   // selected option ids

    init(
        title: String,
        options: [ComponentOption],
        allowsMultiple: Bool,
        current: [ComponentOption],
        onApply: @escaping ([ComponentOption]) -> Void
    ) {
        self.title = title
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.onApply = onApply
        self._draft = State(initialValue: Set(current.map(\.id)))
    }

    var body: some View {
        PickerScaffold(
            title: title,
            confirmTitle: "Apply",
            onConfirm: { onApply(options.filter { draft.contains($0.id) }) }
        ) {
            KeyboardFilterList(
                items: options,
                prompt: "Filter \(title.lowercased())",
                emptyText: "No \(title.lowercased()) defined for this project.",
                filterText: { $0.label },
                onActivate: { activate($0) }
            ) { option in
                HStack {
                    Text(option.label).foregroundStyle(theme.palette.foreground)
                    Spacer()
                    if draft.contains(option.id) {
                        Image(systemName: "checkmark").foregroundStyle(theme.palette.primary)
                    }
                }
                .contentShape(Rectangle())
            }
        }
    }

    private func activate(_ option: ComponentOption) {
        if allowsMultiple {
            if draft.contains(option.id) { draft.remove(option.id) } else { draft.insert(option.id) }
        } else {
            onApply([option])
            dismiss()
        }
    }
}
