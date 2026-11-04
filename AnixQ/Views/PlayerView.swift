import SwiftUI
import WebKit
import AVFoundation

/// Episodes are served by embeddable web players (mostly Kodik), so the video itself is rendered
/// by a WKWebView. Everything around it — episode switching, dubs, history, layout — is native.
struct PlayerView: View {
    let release: Release
    @ObservedObject var model: EpisodesModel

    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var current: Episode
    @State private var isLoadingPage = true
    @State private var reloadToken = 0

    init(release: Release, start: Episode, model: EpisodesModel) {
        self.release = release
        self.model = model
        _current = State(initialValue: start)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if landscape {
                    videoArea
                        .ignoresSafeArea()
                        .overlay(alignment: .topLeading) {
                            closeButton.padding(.leading, 8).padding(.top, 8).opacity(0.75)
                        }
                } else {
                    VStack(spacing: 0) {
                        topBar
                        videoArea
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        ScrollView {
                            controls.padding()
                        }
                    }
                }
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            record(current)
        }
    }

    // MARK: Pieces

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            closeButton
            VStack(alignment: .leading, spacing: 1) {
                Text(release.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text("\(current.name) · \(model.selectedType?.name ?? "")")
                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer()
            Button {
                reloadToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Перезагрузить плеер")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var videoArea: some View {
        ZStack {
            Color.black
            if let url = current.playerURL {
                WebPlayer(url: url, isLoading: $isLoadingPage)
                    .id("\(current.url)#\(reloadToken)")
            } else {
                Text("Некорректная ссылка на серию").foregroundStyle(Theme.secondaryText)
            }
            if isLoadingPage {
                VStack(spacing: 10) {
                    ProgressView().tint(.white).scaleEffect(1.3)
                    Text("Загружаем плеер…").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.name).font(.system(size: 24, weight: .heavy))
                Text(release.title).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(2)
            }

            HStack(spacing: 10) {
                navButton(title: "Назад", icon: "backward.end.fill", episode: model.episode(before: current))
                navButton(title: "Далее", icon: "forward.end.fill", episode: model.episode(after: current), primary: true)
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(model.types) { t in
                        Button {
                            switchType(t)
                        } label: {
                            Label(t.name, systemImage: t.id == model.selectedType?.id ? "checkmark"
                                                       : (t.isSub ? "captions.bubble" : "mic"))
                        }
                    }
                } label: {
                    selector(icon: "mic.fill", title: "Озвучка", value: model.selectedType?.name ?? "—")
                }
                if model.sources.count > 1 {
                    Menu {
                        ForEach(model.sources) { s in
                            Button {
                                switchSource(s)
                            } label: {
                                Label(s.name, systemImage: s.id == model.selectedSource?.id ? "checkmark" : "play.rectangle")
                            }
                        }
                    } label: {
                        selector(icon: "play.rectangle.fill", title: "Плеер", value: model.selectedSource?.name ?? "—")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Серии").font(.headline)
                    Spacer()
                    Text("\(model.episodes.count)").foregroundStyle(Theme.secondaryText)
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(model.episodes) { ep in
                                episodeChip(ep).id(ep.position)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(current.position, anchor: .center) }
                    .onChange(of: current) { ep in
                        withAnimation { proxy.scrollTo(ep.position, anchor: .center) }
                    }
                }
            }

            Label("Если видео не запускается — нажмите ↻ сверху или выберите другую озвучку/плеер.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .foregroundStyle(.white)
    }

    private func navButton(title: String, icon: String, episode: Episode?, primary: Bool = false) -> some View {
        Button {
            if let episode { play(episode) }
        } label: {
            HStack(spacing: 8) {
                if !primary { Image(systemName: icon) }
                Text(title)
                if primary { Image(systemName: icon) }
            }
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(primary ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .opacity(episode == nil ? 0.35 : 1)
        }
        .disabled(episode == nil)
        .buttonStyle(PressableStyle())
    }

    private func selector(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(Theme.secondaryText)
                Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .cardStyle(radius: 14)
        .foregroundStyle(.white)
    }

    private func episodeChip(_ ep: Episode) -> some View {
        let isCurrent = ep.position == current.position
        let watched = history.isWatched(releaseId: release.id, position: ep.position)
        return Button {
            play(ep)
        } label: {
            VStack(spacing: 2) {
                Text("\(ep.position)").font(.system(size: 17, weight: .heavy, design: .rounded))
                Image(systemName: isCurrent ? "play.fill" : (watched ? "checkmark" : "circle"))
                    .font(.system(size: 8, weight: .bold))
                    .opacity(isCurrent || watched ? 1 : 0)
            }
            .frame(width: 56, height: 56)
            .background(isCurrent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(watched && !isCurrent ? Theme.secondaryText : .white)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Actions

    private func play(_ ep: Episode) {
        guard ep != current else { return }
        isLoadingPage = true
        current = ep
        record(ep)
    }

    private func record(_ ep: Episode) {
        if let t = model.selectedType { history.record(release: release, episode: ep, type: t) }
    }

    private func switchType(_ t: VoiceoverType) {
        let position = current.position
        Task {
            await model.select(type: t)
            if let ep = model.episodes.first(where: { $0.position == position }) ?? model.episodes.first {
                isLoadingPage = true
                current = ep
                record(ep)
            }
        }
    }

    private func switchSource(_ s: EpisodeSource) {
        let position = current.position
        Task {
            await model.select(source: s)
            if let ep = model.episodes.first(where: { $0.position == position }) ?? model.episodes.first {
                isLoadingPage = true
                current = ep
                record(ep)
            }
        }
    }
}

// MARK: - Web player

struct WebPlayer: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(initial: url, isLoading: $isLoading) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        // Black page background and no page margins so the player blends with the screen.
        let css = "html,body{background:#000!important;margin:0!important;padding:0!important;overflow:hidden!important}"
        let js = "var s=document.createElement('style');s.innerHTML='\(css)';(document.head||document.documentElement).appendChild(s);"
        config.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let allowedBase: String?
        private var isLoading: Binding<Bool>
        private var didFinishFirstLoad = false

        init(initial: URL, isLoading: Binding<Bool>) {
            self.allowedBase = initial.host.map(Coordinator.baseDomain)
            self.isLoading = isLoading
        }

        static func baseDomain(_ host: String) -> String {
            host.split(separator: ".").suffix(2).joined(separator: ".")
        }

        private func isPlayerHost(_ host: String) -> Bool {
            let base = Coordinator.baseDomain(host)
            return base == allowedBase || host.contains("kodik") || host.contains("aniqit")
                || host.contains("sibnet") || host.contains("libria")
        }

        /// Keeps the main frame on the player: ad scripts love to redirect the whole page.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame ?? false else {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url, let scheme = url.scheme,
               scheme == "http" || scheme == "https" {
                if let host = url.host, !isPlayerHost(host) {
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }
            // about:blank etc. are fine; custom schemes (app-store links, intents) are not.
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishFirstLoad = true
            DispatchQueue.main.async { self.isLoading.wrappedValue = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.isLoading.wrappedValue = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            DispatchQueue.main.async { self.isLoading.wrappedValue = false }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if !didFinishFirstLoad {
                DispatchQueue.main.async { self.isLoading.wrappedValue = true }
            }
        }

        /// Pop-ups (ads) are never opened.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
