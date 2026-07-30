import SwiftUI
import BalmModels
import BalmDesignSystem

struct NativeComponentsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let components: [JiraComponent]
    let onApply: ([String]) -> Void

    @State private var draft: Set<String>
    @State private var searchText = ""

    init(components: [JiraComponent], currentNames: [String], onApply: @escaping ([String]) -> Void) {
        self.components = components
        self.onApply = onApply
        self._draft = State(initialValue: Set(currentNames))
    }

    var body: some View {
        PickerScaffold(
            title: "Components",
            confirmTitle: "Apply",
            onConfirm: { onApply(Array(draft).sorted()) }
        ) {
            List {
                if components.isEmpty {
                    ContentUnavailableView("No components", systemImage: "shippingbox")
                } else {
                    ForEach(filteredComponents, id: \.name) { component in
                        Button {
                            toggle(component.name)
                        } label: {
                            HStack {
                                Text(component.name)
                                Spacer()
                                if draft.contains(component.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.palette.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search components")
        }
    }

    private var filteredComponents: [JiraComponent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return components }
        return components.filter { $0.name.localizedStandardContains(query) }
    }

    private func toggle(_ name: String) {
        if draft.contains(name) { draft.remove(name) } else { draft.insert(name) }
    }
}
