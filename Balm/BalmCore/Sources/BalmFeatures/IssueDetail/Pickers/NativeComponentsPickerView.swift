import SwiftUI
import BalmModels
import BalmDesignSystem

/// Multi-select: Return toggles the highlighted component and keeps the sheet
/// open; ⌘↩ applies.
struct NativeComponentsPickerView: View {
    let components: [JiraComponent]
    let onApply: ([String]) -> Void

    @State private var draft: Set<String>

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
            KeyboardFilterList(
                items: components,
                prompt: "Filter components",
                emptyText: components.isEmpty ? "This project has no components." : "No components match.",
                initialSelection: components.first { draft.contains($0.name) },
                filterText: { $0.name },
                onActivate: { toggle($0.name) }
            ) { component in
                HStack(spacing: 10) {
                    Text(component.name)
                    Spacer()
                    Image(systemName: draft.contains(component.name) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(draft.contains(component.name) ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                }
                .contentShape(Rectangle())
            }
        }
    }

    private func toggle(_ name: String) {
        if draft.contains(name) { draft.remove(name) } else { draft.insert(name) }
    }
}
