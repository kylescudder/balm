import SwiftUI
import BalmModels
import BalmDesignSystem

public struct BoardView: View {
    @Environment(\.balmTheme) private var theme
    let columns: [BoardColumn]
    @Binding var selection: JiraIssue?
    var onColumnViewed: (() -> Void)?
    var onMove: ((String, BoardColumn) -> Void)?

    public init(
        columns: [BoardColumn],
        selection: Binding<JiraIssue?>,
        onColumnViewed: (() -> Void)? = nil,
        onMove: ((String, BoardColumn) -> Void)? = nil
    ) {
        self.columns = columns
        self._selection = selection
        self.onColumnViewed = onColumnViewed
        self.onMove = onMove
    }

    public var body: some View {
        #if os(macOS)
        wideBoard
        #else
        adaptiveBoard
        #endif
    }

    #if os(macOS)
    private var wideBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                ForEach(columns) { column in
                    BoardColumnView(column: column, selection: $selection, onMove: onMove)
                        .frame(width: 280)
                }
            }
            .padding(theme.spacing.m)
        }
    }
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    private var adaptiveBoard: some View {
        if horizontalSizeClass == .regular {
            // iPad in landscape: same horizontal scroll as Mac.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: theme.spacing.m) {
                    ForEach(columns) { column in
                        BoardColumnView(column: column, selection: $selection, onMove: onMove)
                            .frame(width: 280)
                    }
                }
                .padding(theme.spacing.m)
            }
        } else {
            // iPhone / iPad compact: paged TabView, one column fills width.
            TabView {
                ForEach(columns) { column in
                    BoardColumnView(column: column, selection: $selection, onMove: onMove)
                        .padding(theme.spacing.s)
                        .tag(column.id)
                        .onAppear { onColumnViewed?() }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }
    #endif
}
