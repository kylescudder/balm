import SwiftUI
import BalmModels
import BalmDesignSystem

/// Status as a shape. A 1.5 pt ring whose fill shows how far along an issue is
/// and whose colour shows its health, with an optional mark inside. Replaces
/// the status chip in rows, cards, column headers, the inspector, menus and
/// the inbox. Drawn with a tiny `Shape` because SF Symbols stop at half-filled
/// circles; this is the one custom drawing in the design system.
struct StatusGlyph: View {
    @Environment(\.balmTheme) private var theme
    let spec: StatusGlyphSpec
    var size: CGFloat = 14

    init(_ status: String, size: CGFloat = 14) {
        self.spec = StatusNormaliser.glyph(for: status)
        self.size = size
    }

    init(spec: StatusGlyphSpec, size: CGFloat = 14) {
        self.spec = spec
        self.size = size
    }

    var body: some View {
        let color = theme.palette.color(for: spec.health)
        let lineWidth = max(1.25, size * 0.11)
        ZStack {
            switch spec.fill {
            case .full:
                Circle().fill(color)
            case .dotted:
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: lineWidth, dash: [size * 0.16, size * 0.15]))
                    .foregroundStyle(color)
            case .none, .half, .threeQuarters:
                Circle().strokeBorder(color, lineWidth: lineWidth)
            }

            if let fraction = spec.fill.fraction, fraction < 1 {
                ArcFill(fraction: fraction)
                    .fill(color)
                    .padding(size * 0.24)
            }

            switch spec.mark {
            case .check:
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.background)
            case .exclamation:
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .foregroundStyle(color)
            case .cross:
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(color)
            case .none:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A pie slice from twelve o'clock, clockwise, covering `fraction` of the circle.
struct ArcFill: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: centre)
        path.addArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Glyph plus the normalised status name, for places that need the word too:
/// the inspector's status menu, transition pickers, linked issues.
struct StatusLabel: View {
    let status: String
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 6) {
            StatusGlyph(status, size: size)
            Text(StatusNormaliser.normalise(status))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(StatusNormaliser.normalise(status))")
    }
}

extension BalmPalette {
    /// The colour for a health bucket. Active and done share the accent: the
    /// fill fraction tells them apart, the hue says "moving".
    func color(for health: StatusHealth) -> Color {
        switch health {
        case .active, .done: return accent
        case .waiting: return waiting
        case .blocked: return blocked
        case .notStarted, .closed: return neutral
        }
    }
}
