import SwiftUI
import BalmDesignSystem

struct LabelsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let current: [String]
    let onApply: ([String]) -> Void

    @State private var draft: [String]
    @State private var newLabel: String = ""

    init(current: [String], onApply: @escaping ([String]) -> Void) {
        self.current = current
        self.onApply = onApply
        self._draft = State(initialValue: current)
    }

    var body: some View {
        PickerScaffold(
            title: "Labels",
            confirmTitle: "Apply",
            onConfirm: { onApply(draft) }
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                HStack {
                    TextField("Add label", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addLabel)
                    Button("Add") { addLabel() }
                        .disabled(trimmed.isEmpty)
                }

                if draft.isEmpty {
                    Text("No labels.")
                        .foregroundStyle(theme.palette.mutedForeground)
                } else {
                    FlexibleStack(spacing: theme.spacing.xs) {
                        ForEach(draft, id: \.self) { label in
                            HStack(spacing: theme.spacing.xs) {
                                BalmChip(label)
                                Button {
                                    draft.removeAll { $0 == label }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(theme.palette.mutedForeground)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(theme.spacing.l)
        }
    }

    private var trimmed: String {
        newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addLabel() {
        let value = trimmed
        guard !value.isEmpty, !draft.contains(value) else { return }
        draft.append(value)
        newLabel = ""
    }
}
