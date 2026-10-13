import SwiftUI
import AVKit

public struct MediaStageView: View {
    public let src: String?
    public let alt: String
    public let fallbackChar: String

    @State private var isVisible: Bool = false

    public init(src: String?, alt: String = "Media", fallbackChar: String = "字") {
        self.src = src
        self.alt = alt
        self.fallbackChar = fallbackChar
    }

    private var mediaPayload: MediaType {
        guard let src, !src.isEmpty else { return .empty }
        return MediaResolver.resolveMedia(raw: src)
    }

    public var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)

            switch mediaPayload {
            case .empty:
                fallbackGlyph

            case .youtube(let id, _):
                // YouTube: Render high-res thumbnail preview with native play glyph overlay
                let thumbURL = URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
                ZStack {
                    if let thumbURL {
                        remoteImageView(url: thumbURL)
                    } else {
                        fallbackGlyph
                    }

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }

            case .directVideo(let url):
                NativeVideoPlayer(url: url, isPlaying: isVisible)

            case .image(let url):
                remoteImageView(url: url)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    // MARK: - Subviews

    private func remoteImageView(url: URL) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .controlSize(.mini)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallbackGlyph
            @unknown default:
                fallbackGlyph
            }
        }
    }

    private var fallbackGlyph: some View {
        Text(String(fallbackChar.prefix(1)))
            .font(.system(size: 32, weight: .black))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Native Metal/CoreAnimation Backed Looping Player

private struct NativeVideoPlayer: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        if isPlaying {
            view.play(url: url)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if isPlaying {
            uiView.play(url: url)
        } else {
            uiView.stop()
        }
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}

private final class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func play(url: URL) {
        if currentURL == url, queuePlayer?.rate != 0 { return }
        stop()

        self.currentURL = url
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        self.queuePlayer = player
        self.playerLooper = AVPlayerLooper(player: player, templateItem: item)
        self.playerLayer.player = player
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        playerLooper = nil
        playerLayer.player = nil
        currentURL = nil
    }

    deinit {
        stop()
    }
}