import SwiftUI

/// Maps a logical status token (computed in `BalmModels.StatusNormaliser`)
/// to the palette colour the design system exposes.
public extension BalmPalette {
    enum Semantic: String, Sendable {
        case primary
        case destructive
        case chart1
        case chart3
        case chart4
        case chart5
        case neutral
    }

    func color(for token: Semantic) -> Color {
        switch token {
        case .primary:     return primary
        case .destructive: return destructive
        case .chart1:      return chart1
        case .chart3:      return chart3
        case .chart4:      return chart4
        case .chart5:      return chart5
        case .neutral:     return mutedForeground
        }
    }
}
