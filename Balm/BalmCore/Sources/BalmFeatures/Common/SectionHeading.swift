import SwiftUI

/// A section title inside the issue detail: headline weight with an optional
/// count in secondary and an optional trailing action.
struct SectionHeading<Trailing: View>: View {
    let title: String
    let count: Int?
    let trailing: Trailing

    init(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
            if let count {
                Text(count, format: .number)
                    .font(.headline.weight(.regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            trailing
                .controlSize(.small)
        }
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil) {
        self.init(title, count: count) { EmptyView() }
    }
}
