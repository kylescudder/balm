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

/// Label-less multi-select trigger. Inline in filter condition rows, or as a
/// bordered small control in the scope bar (`bordered: true`).
struct KeyboardMultiSelect: View {
    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]
    /// First-letter hotkey that opens this selector while the parent view is up.
    var shortcut: KeyEquivalent? = nil
    var shortcutModifiers: EventModifiers = []
    /// Draw as a bordered small button rather than inline text.
    var bordered = false
    /// Shown when nothing is selected.
    var emptyLabel = "Any"
    /// Plural noun for the "N selected" summary, e.g. "sprints" → "2 sprints".
    var summaryNoun: String? = nil
    /// Called when the popover or sheet closes, so a caller staging edits can
    /// commit them once rather than on every toggle.
    var onDismiss: (() -> Void)? = nil

    @State private var isPresented = false

    var body: some View {
        Group {
            if bordered {
                trigger
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                trigger
                    .buttonStyle(.plain)
            }
        }
        .fixedSize()
        .keyboardShortcutIfPresent(shortcut, modifiers: shortcutModifiers)
        .onChange(of: isPresented) { _, presented in
            if !presented { onDismiss?() }
        }
        #if os(macOS)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            NativeMultiSelectPopover(title: title, options: options, selection: $selection)
                .frame(minWidth: 280, minHeight: 220, maxHeight: 420)
        }
        #else
        .sheet(isPresented: $isPresented) {
            NativeMultiSelectSheet(title: title, options: options, selection: $selection)
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    private var trigger: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 4) {
                Text(summary)
                    .foregroundStyle(textStyle)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(bordered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
        }
        .help(title)
    }

    private var textStyle: AnyShapeStyle {
        if bordered { return AnyShapeStyle(.primary) }
        return selection.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint)
    }

    private var summary: String {
        if selection.isEmpty { return emptyLabel }
        if selection.count == 1,
           let match = options.first(where: { $0.id == selection[0] }) {
            return match.label
        }
        if let summaryNoun { return "\(selection.count) \(summaryNoun)" }
        return "\(selection.count) selected"
    }
}

enum MultiSelectClearPolicy {
    static func shouldShowClearAction(selection: [String], options: [MultiSelectOption]) -> Bool {
        !selection.isEmpty
    }
}

#if os(macOS)
private struct NativeMultiSelectPopover: View {
    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if MultiSelectClearPolicy.shouldShowClearAction(selection: selection, options: options) {
                    Button("Clear") { selection.removeAll() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            NativeMultiSelectList(title: title, options: options, selection: $selection)
        }
    }
}
#endif

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
                            .disabled(!MultiSelectClearPolicy.shouldShowClearAction(selection: selection, options: options))
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
    func keyboardShortcutIfPresent(_ key: KeyEquivalent?, modifiers: EventModifiers = []) -> some View {
        if let key {
            keyboardShortcut(key, modifiers: modifiers)
        } else {
            self
        }
    }
}
