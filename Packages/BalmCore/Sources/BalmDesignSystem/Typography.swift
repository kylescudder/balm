import SwiftUI

public struct Typography: Sendable {
    public let largeTitle: Font
    public let title: Font
    public let title2: Font
    public let title3: Font
    public let headline: Font
    public let body: Font
    public let bodyMono: Font
    public let callout: Font
    public let caption: Font
    public let footnote: Font
}

public extension Typography {
    static let `default` = Typography(
        largeTitle: .system(.largeTitle, design: .default, weight: .semibold),
        title:      .system(.title, design: .default, weight: .semibold),
        title2:     .system(.title2, design: .default, weight: .semibold),
        title3:     .system(.title3, design: .default, weight: .semibold),
        headline:   .system(.headline, design: .default, weight: .semibold),
        body:       .system(.body, design: .default),
        bodyMono:   .system(.body, design: .monospaced),
        callout:    .system(.callout, design: .default),
        caption:    .system(.caption, design: .default),
        footnote:   .system(.footnote, design: .default)
    )
}
