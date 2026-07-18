import SwiftUI

struct LabelsEditorView: View {
    @Environment(\.dismiss) private var dismiss

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
            Form {
                Section("Add Label") {
                    HStack {
                        TextField("Label", text: $newLabel)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .onSubmit(addLabel)
                        Button("Add") { addLabel() }
                            .disabled(trimmed.isEmpty)
                    }
                }

                Section("Current Labels") {
                    if draft.isEmpty {
                        ContentUnavailableView("No labels", systemImage: "tag")
                    } else {
                        ForEach(draft, id: \.self) { label in
                            Text(label)
                        }
                        .onDelete { offsets in
                            draft.remove(atOffsets: offsets)
                        }
                    }
                }
            }
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
