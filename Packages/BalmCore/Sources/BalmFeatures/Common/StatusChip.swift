import SwiftUI
import BalmModels
import BalmDesignSystem

struct StatusChip: View {
    @Environment(\.balmTheme) private var theme
    let status: String

    var body: some View {
        let token = StatusNormaliser.semanticTokenName(status)
        let semantic = BalmPalette.Semantic.from(token)
        BalmChip(StatusNormaliser.normalise(status), tint: theme.palette.color(for: semantic))
            .accessibilityLabel("Status: \(StatusNormaliser.normalise(status))")
    }
}

extension BalmPalette.Semantic {
    static func from(_ token: StatusSemanticToken) -> BalmPalette.Semantic {
        switch token {
        case .primary: return .primary
        case .destructive: return .destructive
        case .chart1: return .chart1
        case .chart3: return .chart3
        case .chart4: return .chart4
        case .chart5: return .chart5
        case .neutral: return .neutral
        }
    }
}
