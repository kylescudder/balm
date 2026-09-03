import SwiftUI

/// The field has focus on arrival: type a label, Return adds it, keep typing.
/// ⌘↩ applies the list.
struct LabelsEditorView: View {
    let current: [String]
    let onApply: ([String]) -> Void

    @State private var draft: [String]
    @State private var newLabel: String = ""
    @FocusState private var fieldFocused: Bool

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
                Section {
                    HStack {
                        TextField("Add a label", text: $newLabel)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .focused($fieldFocused)
                            .onSubmit(addLabel)
                        Button("Add") { addLabel() }
                            .disabled(trimmed.isEmpty)
                    }
                } footer: {
                    Text("Return adds the label. ⌘↩ applies.")
                }

                Section("Labels") {
                    if draft.isEmpty {
                        Text("No labels yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft, id: \.self) { label in
                            HStack {
                                Text(label)
                                Spacer()
                                Button {
                                    draft.removeAll { $0 == label }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(label)")
                            }
                        }
                        .onDelete { offsets in
                            draft.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { fieldFocused = true }
        }
    }

    private var trimmed: String {
        newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addLabel() {
        let value = trimmed
        guard !value.isEmpty else { return }
        if !draft.contains(value) { draft.append(value) }
        newLabel = ""
        fieldFocused = true
    }
}
