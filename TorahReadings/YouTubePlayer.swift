import SwiftUI
import WebKit

/// Embeds one YouTube video inline. YouTube refuses embeds that have no
/// referring page (error 153), so the HTML is loaded with an https base URL.
struct YouTubePlayer: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loaded != videoID else { return }
        context.coordinator.loaded = videoID
        let origin = "https://mikemadden-looping.github.io"
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&cc_load_policy=0&modestbranding=1&origin=\(origin)"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: origin))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded: String? }
}
