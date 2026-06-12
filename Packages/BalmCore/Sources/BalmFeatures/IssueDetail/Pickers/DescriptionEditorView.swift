import SwiftUI
import BalmDesignSystem

struct DescriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let initial: String
    let onApply: (String) -> Void

    @State private var text: String

    init(initial: String, onApply: @escaping (String) -> Void) {
        self.initial = initial
        self.onApply = onApply
        self._text = State(initialValue: initial)
    }

    var body: some View {
        PickerScaffold(
            title: "Description",
            confirmTitle: "Save",
            canConfirm: text != initial,
            onConfirm: { onApply(text) }
        ) {
            TextEditor(text: $text)
                .font(theme.typography.body)
                .padding(theme.spacing.m)
        }
    }
}
