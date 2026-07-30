import SwiftUI
import BalmModels
import BalmDesignSystem

/// In-app viewer for image attachments. Loads the full-resolution content via
/// the authed gateway and supports pinch-to-zoom. Escape (or Done) dismisses.
struct ImageViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: JiraAttachmentMeta

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var aspect: CGFloat?

    /// Sheet content size that hugs the image's aspect ratio, bounded so it
    /// never exceeds a sensible on-screen size. Falls back to a 3:2 box until
    /// the image loads and reports its true dimensions.
    private var imageSize: CGSize {
        let maxW: CGFloat = 1280, maxH: CGFloat = 820, minDim: CGFloat = 360
        guard let aspect, aspect > 0 else { return CGSize(width: 960, height: 640) }
        var w = maxW
        var h = w / aspect
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        return CGSize(width: max(w, minDim), height: max(h, minDim))
    }

    var body: some View {
        NavigationStack {
            JiraImageView(url: attachment.content, contentMode: .fit, onLoad: { size in
                if size.height > 0 {
                    withAnimation(.easeInOut(duration: 0.2)) { aspect = size.width / size.height }
                }
            }) { reason in
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(reason ?? "Couldn't load image.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scaleEffect(zoom)
            .frame(width: imageSize.width, height: imageSize.height)
            .clipped()
            .background(Color.black)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(max(committedZoom * value.magnification, 1), 6)
                    }
                    .onEnded { _ in committedZoom = zoom }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.25)) {
                    zoom = zoom > 1 ? 1 : 2
                    committedZoom = zoom
                }
            }
            .navigationTitle(attachment.filename)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
