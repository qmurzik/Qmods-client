import SwiftUI
import WebKit
import AVFoundation

/// Anixart episodes are served through embeddable web players (Kodik, Sibnet, AniLibria...),
/// so playback happens inside a WKWebView with inline + native fullscreen video enabled.
struct PlayerView: View {
    let episodes: [Episode]
    let onPlay: (Episode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current: Episode
    @State private var releaseTitle: String

    init(item: PlayerItem, episodes: [Episode], onPlay: @escaping (Episode) -> Void) {
        self.episodes = episodes
        self.onPlay = onPlay
        _current = State(initialValue: item.episode)
        _releaseTitle = State(initialValue: item.releaseTitle)
    }

    private var index: Int? { episodes.firstIndex { $0.position == current.position } }
    private var previous: Episode? { index.flatMap { $0 > 0 ? episodes[$0 - 1] : nil } }
    private var next: Episode? { index.flatMap { $0 + 1 < episodes.count ? episodes[$0 + 1] : nil } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(releaseTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(current.name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { if let previous { play(previous) } } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(previous == nil)
                    Button { if let next { play(next) } } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(next == nil)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .foregroundStyle(.white)

                if let url = current.playerURL {
                    WebPlayer(url: url)
                        .id(current.url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Spacer()
                    Text("Некорректная ссылка на серию").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            onPlay(current)
        }
    }

    private func play(_ ep: Episode) {
        current = ep
        onPlay(ep)
    }
}

struct WebPlayer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(host: url.host) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        // Block pop-up windows opened by player ads.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let host: String?
        init(host: String?) { self.host = host }

        // Keep top-level navigation inside the player; drop redirects to ad/landing pages.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            if isMainFrame, navigationAction.navigationType == .linkActivated,
               let target = navigationAction.request.url?.host, target != host {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
