import SwiftUI
import BalmModels
import BalmDesignSystem

public struct BoardView: View {
    let columns: [BoardColumn]
    @Binding var columnSelection: String?
    var onColumnViewed: (() -> Void)?
    var onMove: ((String, BoardColumn) -> Void)?

    public init(
        columns: [BoardColumn],
        columnSelection: Binding<String?>,
        onColumnViewed: (() -> Void)? = nil,
        onMove: ((String, BoardColumn) -> Void)? = nil
    ) {
        self.columns = columns
        self._columnSelection = columnSelection
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

    private var wideBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in
                    BoardColumnView(column: column, onMove: onMove)
                        .frame(width: 268)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(BalmSurface.window)
    }

    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    private var adaptiveBoard: some View {
        if horizontalSizeClass == .regular {
            wideBoard
        } else {
            // iPhone: one column per page.
            TabView(selection: $columnSelection) {
                ForEach(columns) { column in
                    BoardColumnView(column: column, onMove: onMove)
                        .padding(.horizontal, 10)
                        .tag(Optional(column.id))
                        .onAppear { onColumnViewed?() }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(BalmSurface.window)
        }
    }
    #endif
}
