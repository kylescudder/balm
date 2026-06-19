import SwiftUI

/// One selectable row in a `KeyboardSelectMenu`.
struct MultiSelectOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Native-*looking* but custom-*behaved* multi-select dropdown, built for the
/// app's fully keyboard-accessible (Linear-style) UX.
///
/// A native `Menu` can't be opened by a `.keyboardShortcut` (no public API), so
/// this wraps a `Button` — which *can* carry a shortcut — over a `.popover`
/// holding a focusable `List`. The result reads as a stock control but behaves
/// like a Linear dropdown:
///   • `shortcut` opens it while the parent view is on screen
///   • ↑/↓ move the highlight, and typing jumps to a row (both `List`-native)
///   • Return / Space toggle the highlighted row; the menu stays open
///   • multi-select — checkmarks show membership, independent of the highlight
///   • Esc / click-away dismiss (popover default)
///
/// Drop-in shape: same API as a labelled form row, so it slots into a `Form`.
/// Wraps the standalone `KeyboardMultiSelect` button in a `LabeledContent`.
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

/// The label-less popover multi-select button. Same keyboard behaviour as
/// `KeyboardSelectMenu` but without the `LabeledContent` wrapper, so it can sit
/// inline in a condition row (where the field name is already shown).
struct KeyboardMultiSelect: View {
    let title: String
    let options: [MultiSelectOption]
    @Binding var selection: [String]
    /// First-letter hotkey that opens this menu while the parent view is up.
    var shortcut: KeyEquivalent? = nil

    @State private var isPresented = false
    /// Row the keyboard highlight sits on (drives ↑/↓ + type-select via `List`
    /// single-selection); membership in `selection` is separate.
    @State private var highlight: String?
    @FocusState private var listFocused: Bool

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
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { popoverBody }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !selection.isEmpty {
                Button("Clear", role: .destructive) { selection.removeAll() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            if options.isEmpty {
                Text("No values")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                List(selection: $highlight) {
                    ForEach(options) { option in
                        HStack {
                            Text(option.label)
                            Spacer()
                            if selection.contains(option.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(option.id)
                        .onTapGesture { toggle(option.id) }
                    }
                }
                .listStyle(.plain)
                .focused($listFocused)
                .onKeyPress(.return) { toggleHighlighted() }
                .onKeyPress(.space) { toggleHighlighted() }
            }
        }
        .frame(minWidth: 240, minHeight: 120, maxHeight: 360)
        .onAppear {
            highlight = selection.first ?? options.first?.id
            listFocused = true
        }
    }

    /// Toggle the highlighted row; `.handled` stops the key bubbling (e.g. Space
    /// scrolling the `List`).
    private func toggleHighlighted() -> KeyPress.Result {
        guard let highlight else { return .ignored }
        toggle(highlight)
        return .handled
    }

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
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
