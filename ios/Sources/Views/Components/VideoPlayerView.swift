import SwiftUI
import WebKit
import AVKit

public struct VideoPlayerView: View {
    public let src: String
    public let accentColor: Color
    public var fallbackText: String = "No video link provided."

    @State private var isActivated: Bool = false

    public init(src: String, accentColor: Color, fallbackText: String = "No video link provided.") {
        self.src = src
        self.accentColor = accentColor
        self.fallbackText = fallbackText
    }

    private var youtubeId: String? {
        guard let url = URL(string: src) else { return nil }
        if url.host?.contains("youtube.com") == true {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                return components.queryItems?.first(where: { $0.name == "v" })?.value
            }
        } else if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }
        return nil
    }

    public var body: some View {
        ZStack {
            Color.black

            if src.isEmpty {
                Text(fallbackText)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            } else if let ytId = youtubeId {
                if !isActivated {
                    // Lazy Thumbnail Façade
                    Button {
                        isActivated = true
                    } label: {
                        ZStack {
                            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(ytId)/hqdefault.jpg")) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure, .empty:
                                    Color.black
                                @unknown default:
                                    Color.black
                                }
                            }

                            // Translucent Play Pedestal
                            Circle()
                                .fill(accentColor)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: 2)
                                )
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Real Inline WebKit Player with autoplay
                    YouTubeWebPlayer(videoId: ytId)
                }
            } else if let videoURL = URL(string: src), src.hasSuffix(".mp4") || src.hasSuffix(".m3u8") {
                VideoPlayer(player: AVPlayer(url: videoURL))
            } else {
                Link(destination: URL(string: src) ?? URL(string: "https://youtube.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open Video in Browser")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .foregroundStyle(accentColor)
                    .clipShape(Capsule())
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct YouTubeWebPlayer: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false

        let embedHTML = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
        <style>body { margin: 0; background-color: #000; overflow: hidden; }</style>
        </head>
        <body>
        <iframe width="100%" height="100%" src="https://www.youtube.com/embed/\(videoId)?autoplay=1&playsinline=1&rel=0" frameborder="0" allow="autoplay; encrypted-media" allowfullscreen></iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(embedHTML, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}