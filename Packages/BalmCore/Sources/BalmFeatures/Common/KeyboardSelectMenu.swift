import SwiftUI

/// One selectable row in a filter value selector.
struct MultiSelectOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Native multi-select form row used by the filter builder.
struct KeyboardSelectMenu: View {
    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]
    /// First-letter hotkey that opens this menu while the parent view is up.
    var shortcut: KeyEquivalent? = nil

    var body: some View {
        LabeledContent(title) {
            KeyboardMultiSelect(
                title: title,
                options: options,
                selection: $selection,
                shortcut: shortcut
            )
        }
    }
}

/// Label-less multi-select trigger for inline filter condition rows.
struct KeyboardMultiSelect: View {
    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]
    /// First-letter hotkey that opens this selector while the parent view is up.
    var shortcut: KeyEquivalent? = nil

    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 4) {
                Text(summary)
                    .foregroundStyle(selection.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .keyboardShortcutIfPresent(shortcut)
        #if os(macOS)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            NativeMultiSelectList(title: title, options: options, selection: $selection)
                .frame(minWidth: 280, minHeight: 220, maxHeight: 420)
        }
        #else
        .sheet(isPresented: $isPresented) {
            NativeMultiSelectSheet(title: title, options: options, selection: $selection)
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    private var summary: String {
        if selection.isEmpty { return "Any" }
        if selection.count == 1,
           let match = options.first(where: { $0.id == selection[0] }) {
            return match.label
        }
        return "\(selection.count) selected"
    }
}

private struct NativeMultiSelectList: View {
    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]

    var body: some View {
        List {
            if options.isEmpty {
                Text("No values")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    Button { toggle(option.id) } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if selection.contains(option.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(title)
    }

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}

#if !os(macOS)
private struct NativeMultiSelectSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]

    var body: some View {
        NavigationStack {
            NativeMultiSelectList(title: title, options: options, selection: $selection)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") { selection.removeAll() }
                            .disabled(selection.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
#endif

private extension View {
    @ViewBuilder
    func keyboardShortcutIfPresent(_ key: KeyEquivalent?) -> some View {
        if let key {
            keyboardShortcut(key, modifiers: [])
        } else {
            self
        }
    }
}
