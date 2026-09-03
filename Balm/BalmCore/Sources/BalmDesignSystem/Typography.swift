import SwiftUI

/// Balm's type is the system's Dynamic Type ramp in SF Pro, with one serif
/// moment: the issue title and the wordmark are set in New York. Nothing else
/// is serif, and nothing uses a fixed point size.
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

    /// The document title of the issue being read. New York, semibold.
    public let issueTitle: Font
    /// "Balm." on the login screen and the iPad sidebar. New York, bold.
    public let wordmark: Font
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
        footnote:   .system(.footnote, design: .default),
        issueTitle: .system(.title2, design: .serif, weight: .semibold),
        wordmark:   .system(.largeTitle, design: .serif, weight: .bold)
    )
}
