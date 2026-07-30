import SwiftUI
import BalmModels

/// One selectable option for the create modal's component field, addressed by
/// the Jira option `id` (submitted) with a human `label` (displayed/filtered).
struct ComponentOption: Hashable, Identifiable {
    let id: String
    let label: String
}

/// Native component picker for single- and multi-select Jira component fields.
struct ComponentsPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [ComponentOption]
    let allowsMultiple: Bool
    let onApply: ([ComponentOption]) -> Void

    @State private var draft: Set<String>
    @State private var searchText = ""

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
            confirmTitle: allowsMultiple ? "Apply" : nil,
            onConfirm: { onApply(options.filter { draft.contains($0.id) }) }
        ) {
            List {
                if filteredOptions.isEmpty {
                    ContentUnavailableView("No \(title.lowercased())", systemImage: "shippingbox")
                } else {
                    ForEach(filteredOptions) { option in
                        Button {
                            activate(option)
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                if draft.contains(option.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
        }
    }

    private var filteredOptions: [ComponentOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { $0.label.localizedStandardContains(query) }
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
