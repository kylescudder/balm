import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        Label("Offline. Showing what was loaded last.", systemImage: "wifi.slash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}
