import SwiftUI
import BalmDesignSystem

struct DueDatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.balmTheme) private var theme

    let currentValue: String?
    let onApply: (String?) -> Void

    @State private var hasDate: Bool
    @State private var date: Date

    init(currentValue: String?, onApply: @escaping (String?) -> Void) {
        self.currentValue = currentValue
        self.onApply = onApply
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        let parsed = currentValue.flatMap { parser.date(from: $0) }
        self._hasDate = State(initialValue: parsed != nil)
        self._date = State(initialValue: parsed ?? .now)
    }

    var body: some View {
        PickerScaffold(
            title: "Due Date",
            confirmTitle: "Apply",
            onConfirm: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                onApply(hasDate ? formatter.string(from: date) : nil)
            }
        ) {
            Form {
                Toggle("Set due date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
        }
    }
}
