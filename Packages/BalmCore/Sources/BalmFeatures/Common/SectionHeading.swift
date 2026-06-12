import SwiftUI
import BalmDesignSystem

struct SectionHeading: View {
    @Environment(\.balmTheme) private var theme
    let title: String
    let trailing: AnyView?

    init(_ title: String, trailing: (some View)? = Optional<EmptyView>.none) {
        self.title = title
        self.trailing = trailing.map { AnyView($0) }
    }

    var body: some View {
        HStack {
            Text(title)
                .font(theme.typography.headline)
                .foregroundStyle(theme.palette.foreground)
            Spacer()
            trailing
        }
    }
}
