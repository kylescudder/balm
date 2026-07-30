import SwiftUI
import BalmDesignSystem

struct OfflineBanner: View {
    @Environment(\.balmTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "wifi.slash")
            Text("Offline — showing cached data.")
                .font(theme.typography.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(theme.palette.destructiveForeground)
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
        .background(theme.palette.destructive)
    }
}
