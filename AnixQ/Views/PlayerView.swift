import SwiftUI
import WebKit
import AVFoundation

/// Player screen.
///
/// The video view keeps the same identity in portrait and landscape: only the chrome around it
/// is added or removed. Re-creating it on rotation is what broke fullscreen before (AVKit's
/// fullscreen controller and the web player were destroyed mid-playback).
struct PlayerView: View {
    let release: Release
    @ObservedObject var model: EpisodesModel

    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var native = NativePlaybackController()
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
            VStack(spacing: 0) {
                if !landscape { topBar }
                videoArea(landscape: landscape)
                    .frame(width: geo.size.width,
                           height: landscape ? geo.size.height : geo.size.width * 9 / 16)
                    .overlay(alignment: .top) {
                        if landscape && !current.isLibria { landscapeBar }
                    }
                if !landscape {
                    ScrollView { controls.padding() }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            AdBlocker.shared.warmUp()
            record(current)
        }
        .onDisappear {
            native.stop()
            OrientationController.set(.portrait)
        }
        .onChange(of: native.finishedCount) { _ in
            if let next = model.episode(after: current) { play(next) }
        }
        .task(id: current.url) {
            if current.isLibria {
                await native.load(current)
                if let next = model.episode(after: current), let url = next.playerURL {
                    LibriaResolver.prefetch(url)
                }
            } else {
                native.stop()
                // Safety net: never leave the spinner over a web player that is already usable.
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { isLoadingPage = false }
            }
        }
    }

    // MARK: Chrome

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            roundButton("chevron.down") { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text(release.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text("\(current.name) · \(model.selectedType?.name ?? "")")
                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer()
            roundButton("arrow.clockwise") { reload() }
                .accessibilityLabel("Перезагрузить")
            roundButton("arrow.up.left.and.arrow.down.right") { OrientationController.set(.landscape) }
                .accessibilityLabel("Во весь экран")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Small bar in landscape: leaves the player's own controls untouched.
    private var landscapeBar: some View {
        HStack(spacing: 10) {
            Button {
                OrientationController.set(.portrait)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Свернуть")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
            }
            if let next = model.episode(after: current) {
                Button {
                    play(next)
                } label: {
                    HStack(spacing: 6) {
                        Text("Серия \(next.position)")
                        Image(systemName: "forward.end.fill")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.top, 6)
        .opacity(0.85)
    }

    // MARK: Video

    private func videoArea(landscape: Bool) -> some View {
        ZStack {
            Color.black
            // Both players stay in the hierarchy; only the active one is visible. This keeps
            // their identity stable across rotations and episode switches.
            NativePlayerView(controller: native, isFullscreen: landscape) {
                OrientationController.set(landscape ? .portrait : .landscape)
            }
            .opacity(current.isLibria ? 1 : 0)
            .allowsHitTesting(current.isLibria)

            if !current.isLibria, let url = current.playerURL {
                WebPlayer(url: url, isLoading: $isLoadingPage)
                    .id("\(current.url)#\(reloadToken)")
            }

            if current.isLibria {
                if let error = native.error {
                    errorOverlay(error)
                }
            } else if isLoadingPage {
                loadingOverlay
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if current.isLibria && native.inSkipRange {
                Button {
                    native.skipOpening()
                } label: {
                    HStack(spacing: 6) {
                        Text("Пропустить опенинг")
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
                }
                .padding(.trailing, 14)
                .padding(.bottom, 64)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: native.inSkipRange)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.white).scaleEffect(1.3)
            Text("Загружаем видео…").font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .allowsHitTesting(false)
    }

    private func errorOverlay(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(Theme.accent)
            Text(error).font(.footnote).multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            Button("Повторить") { reload() }.buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: Controls (portrait)

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
                    ForEach(model.sortedTypes) { t in
                        Button {
                            switchType(t)
                        } label: {
                            Label(model.nativeTypeIds.contains(t.id) ? "⚡ \(t.name) · без рекламы" : t.name,
                                  systemImage: t.id == model.selectedType?.id ? "checkmark"
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
                                Label(EpisodesModel.isNativeSource(s) ? "⚡ \(s.name) · без рекламы" : "\(s.name) · с рекламой",
                                      systemImage: s.id == model.selectedSource?.id ? "checkmark" : "play.rectangle")
                            }
                        }
                    } label: {
                        selector(icon: "play.rectangle.fill", title: "Плеер", value: model.selectedSource?.name ?? "—")
                    }
                }
            }

            if current.isLibria && !native.qualities.isEmpty {
                Menu {
                    ForEach(native.qualities) { q in
                        Button {
                            native.select(q)
                        } label: {
                            Label(q.label, systemImage: q == native.selectedQuality ? "checkmark" : "sparkles.tv")
                        }
                    }
                } label: {
                    selector(icon: "sparkles.tv.fill", title: "Качество", value: native.selectedQuality?.label ?? "—")
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

            Label(current.isLibria
                  ? "Libria играет во встроенном плеере iOS. Во весь экран — кнопка ⤢ сверху или просто поверните телефон."
                  : "Kodik — сторонний плеер с рекламой, старт может занимать до минуты. Быстрее и без рекламы — озвучки с ⚡ (Libria/Liberty).",
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

    private func reload() {
        if current.isLibria {
            native.reload()
        } else {
            isLoadingPage = true
            reloadToken += 1
        }
    }

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

// MARK: - Orientation

enum OrientationController {
    enum Target { case portrait, landscape }

    static func set(_ target: Target) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let mask: UIInterfaceOrientationMask = target == .landscape ? .landscapeRight : .portrait
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            window.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
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
        // Element fullscreen inside an embedded WKWebView ignores rotation (the "vertical
        // fullscreen" bug). With it off, the player falls back to the native iOS video
        // fullscreen, and the app's own fullscreen button rotates the whole screen.
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = false
        }

        // Media events from every frame (the video lives in Kodik's cross-origin iframe) are
        // reported back for the debug log: this is how the CI test sees whether video starts.
        var probe = """
        (function(){
          function post(m){ try{ window.webkit.messageHandlers.dbg.postMessage(m); }catch(e){} }
          ['playing','waiting','error','loadedmetadata','stalled'].forEach(function(ev){
            document.addEventListener(ev, function(e){
              var t=e.target; if(!(t instanceof HTMLMediaElement)) return;
              post(ev+' '+location.host+' '+((t&&t.currentSrc)||'').slice(0,80));
            }, true);
          });
        })();
        """
        if UserDefaults.standard.bool(forKey: "debugAutoClick") {
            probe += """
            setTimeout(function(){
              var b=document.querySelector('.play_button, .play_background, .fp-ui, video');
              if(b){ b.click(); window.webkit.messageHandlers.dbg.postMessage('autoclick '+location.host+' '+b.className); }
            }, 5000);
            """
        }
        config.userContentController.addUserScript(
            WKUserScript(source: probe, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        config.userContentController.add(context.coordinator, name: "dbg")

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

        // Kodik refuses to render outside an iframe ("данной страницы не существует"),
        // so the player is embedded the way it is designed to be used.
        let src = url.absoluteString.replacingOccurrences(of: "\"", with: "&quot;")
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="\(src)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen
          referrerpolicy="origin"></iframe>
        </body></html>
        """
        DebugLog.log("web: load \(url.absoluteString)")
        Task { @MainActor in
            if AdBlocker.isEnabled, let rules = await AdBlocker.shared.rules() {
                web.configuration.userContentController.add(rules)
            }
            web.loadHTMLString(html, baseURL: URL(string: "https://anixart.tv/"))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "dbg")
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            DebugLog.log("web: \(message.body)")
        }

        private let allowedBase: String?
        private var isLoading: Binding<Bool>

        init(initial: URL, isLoading: Binding<Bool>) {
            self.allowedBase = initial.host.map(Coordinator.baseDomain)
            self.isLoading = isLoading
        }

        static func baseDomain(_ host: String) -> String {
            host.split(separator: ".").suffix(2).joined(separator: ".")
        }

        private func isPlayerHost(_ host: String) -> Bool {
            let base = Coordinator.baseDomain(host)
            return base == allowedBase || base == "anixart.tv" || host.contains("kodik") || host.contains("aniqit")
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
                    DebugLog.log("web: blocked main-frame redirect to \(host)")
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DebugLog.log("web: didFinish")
            DispatchQueue.main.async { self.isLoading.wrappedValue = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.isLoading.wrappedValue = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            DispatchQueue.main.async { self.isLoading.wrappedValue = false }
        }

        /// Pop-ups (ads) are never opened.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
