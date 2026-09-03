import SwiftUI

/// Keyboard-first filterable list for picker sheets, matching the app's
/// Linear-style UX. An auto-focused search field filters rows by substring;
/// ↑/↓ move a highlight (wrapping); Return activates the highlighted row;
/// Esc dismisses. The search field keeps focus throughout, so the whole flow
/// is mouse-free — though clicking a row activates it too.
///
/// Identity is the value itself (`Hashable`), so callers pass model values
/// directly, or a small enum that folds in synthetic rows (Unassigned,
/// Backlog). `onActivate` decides what activation means: single-select pickers
/// select-and-dismiss; multi-select pickers toggle membership and stay open.
struct KeyboardFilterList<Item: Hashable, Row: View>: View {
    @Environment(\.dismiss) private var dismiss

    let items: [Item]
    var prompt: String = "Filter"
    var isLoading: Bool = false
    var emptyText: String = "No matches."
    /// Currently-selected item, used to seed the highlight on first appearance.
    var initialSelection: Item? = nil
    /// Text each item is matched against, case-insensitively.
    let filterText: (Item) -> String
    let onActivate: (Item) -> Void
    @ViewBuilder let row: (Item) -> Row

    @State private var query = ""
    @State private var highlight: Item?
    @FocusState private var searchFocused: Bool

    private var filtered: [Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { filterText($0).lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            listBody
        }
        .onAppear { searchFocused = true; reseed() }
        .onChange(of: items) { _, _ in reseed() }
        .onChange(of: query) { _, _ in reseed() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.return) { activateHighlighted() }
                .onKeyPress(.escape) { dismiss(); return .handled }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var listBody: some View {
        if isLoading && items.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            Text(emptyText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(filtered, id: \.self) { item in
                        Button { onActivate(item) } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(item == highlight ? Color.accentColor.opacity(0.14) : Color.clear)
                        .id(item)
                    }
                }
                .listStyle(.plain)
                .onChange(of: highlight) { _, new in
                    guard let new else { return }
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
    }

    /// Move the highlight by `delta`, wrapping around the filtered rows.
    private func move(_ delta: Int) -> KeyPress.Result {
        let rows = filtered
        guard !rows.isEmpty else { return .ignored }
        if let current = highlight, let idx = rows.firstIndex(of: current) {
            highlight = rows[(idx + delta + rows.count) % rows.count]
        } else {
            highlight = delta > 0 ? rows.first : rows.last
        }
        return .handled
    }

    private func activateHighlighted() -> KeyPress.Result {
        guard let highlight, filtered.contains(highlight) else { return .ignored }
        onActivate(highlight)
        return .handled
    }

    /// Keep the highlight on a still-visible row; otherwise seed it from the
    /// current selection (if visible) or the first match.
    private func reseed() {
        if let highlight, filtered.contains(highlight) { return }
        if let initialSelection, filtered.contains(initialSelection) {
            highlight = initialSelection
        } else {
            highlight = filtered.first
        }
    }
}
