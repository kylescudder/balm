import SwiftUI
import BalmDesignSystem

/// Reusable sheet scaffold: nav title, Cancel button on leading, optional
/// confirmation button on trailing. Body is the picker's contents.
struct PickerScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let title: String
    let confirmTitle: String?
    let onConfirm: (() -> Void)?
    let canConfirm: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        confirmTitle: String? = nil,
        canConfirm: Bool = true,
        onConfirm: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.canConfirm = canConfirm
        self.onConfirm = onConfirm
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if let confirmTitle, let onConfirm {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(confirmTitle) {
                                onConfirm()
                                dismiss()
                            }
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("\(confirmTitle) (⌘↩)")
                            .disabled(!canConfirm)
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}

/// What the metadata panel is currently editing — drives a single `.sheet`.
enum EditableField: String, Identifiable, CaseIterable {
    case status, assignee, priority, sprint, components, versions
    case labels, dueDate, description
    var id: String { rawValue }
}
