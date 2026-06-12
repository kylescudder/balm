import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Decodes raw bytes into a SwiftUI `Image` plus its pixel size, cross-platform.
func decodeImage(_ data: Data) -> (image: Image, size: CGSize)? {
    #if canImport(AppKit)
    guard let img = NSImage(data: data) else { return nil }
    return (Image(nsImage: img), img.size)
    #elseif canImport(UIKit)
    guard let img = UIImage(data: data) else { return nil }
    return (Image(uiImage: img), img.size)
    #else
    return nil
    #endif
}

/// Loads an image from a Bearer-authed, gateway-routed Jira attachment URL and
/// renders it. Shows a spinner while loading and `placeholder` on failure.
struct JiraImageView<Placeholder: View>: View {
    @Environment(AppEnvironment.self) private var env

    let url: URL?
    var contentMode: ContentMode = .fill
    var onLoad: ((CGSize) -> Void)? = nil
    @ViewBuilder var placeholder: (String?) -> Placeholder

    @State private var image: Image?
    @State private var failure: String?

    var body: some View {
        Group {
            if let image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else if let failure {
                placeholder(failure)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        failure = nil
        guard let url else { failure = "No image URL."; return }
        do {
            let data = try await env.api.attachmentData(url: url)
            if let decoded = decodeImage(data) {
                image = decoded.image
                onLoad?(decoded.size)
            } else {
                failure = "Not a decodable image (\(data.count) bytes)."
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
