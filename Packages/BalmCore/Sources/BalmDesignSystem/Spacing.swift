import SwiftUI

public struct Spacing: Sendable {
    public let xs: CGFloat
    public let s: CGFloat
    public let m: CGFloat
    public let l: CGFloat
    public let xl: CGFloat
    public let xxl: CGFloat
}

public extension Spacing {
    static let `default` = Spacing(xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32)
}

public struct Radii: Sendable {
    public let sm: CGFloat
    public let md: CGFloat
    public let lg: CGFloat
}

public extension Radii {
    /// Mirrors `--radius-sm`/`--radius-md`/`--radius-lg` derived from `--radius: 0.5rem`
    /// in `globals.css:49-51`. 0.5rem → 8pt at default body size.
    static let `default` = Radii(sm: 4, md: 6, lg: 8)
}
