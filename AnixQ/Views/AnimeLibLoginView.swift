import SwiftUI
import WebKit

/// Sign-in to AnimeLib on the official site inside a web view. The user types the password into
/// anilib.me itself; the app only picks up the resulting API token from the site's local storage.
struct AnimeLibLoginView: View {
    var onDone: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Войдите в свой аккаунт на сайте AnimeLib"
    @State private var finished = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Theme.card)
                LoginWebView { access, refresh in
                    guard !finished else { return }
                    finished = true
                    AnimeLibSession.token = access
                    AnimeLibSession.refreshToken = refresh
                    status = "Готово, проверяем аккаунт…"
                    DebugLog.log("animelib: token received")
                    Task {
                        AnimeLibSession.username = await AnimeLibAPI.me() ?? "AnimeLib"
                        onDone(true)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Вход в AnimeLib")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onDone(false)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LoginWebView: UIViewRepresentable {
    let onToken: (String, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: URL(string: "https://anilib.me/ru")!))
        context.coordinator.start(polling: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onToken: (String, String?) -> Void
        var timer: Timer?

        init(onToken: @escaping (String, String?) -> Void) { self.onToken = onToken }

        /// Every value in localStorage that mentions an access token (the site keeps its auth
        /// state as JSON there after the OAuth redirect).
        private let script = """
        (function(){
          var out=[];
          for (var i=0;i<localStorage.length;i++){
            var v=localStorage.getItem(localStorage.key(i));
            if (v && v.indexOf('access_token')>=0) out.push(v);
          }
          return JSON.stringify(out);
        })()
        """

        func start(polling web: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak web] _ in
                guard let self, let web else { return }
                web.evaluateJavaScript(self.script) { result, _ in
                    guard let text = result as? String, let data = text.data(using: .utf8),
                          let values = try? JSONSerialization.jsonObject(with: data) as? [String] else { return }
                    for value in values {
                        guard let d = value.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: d),
                              let access = Self.find("access_token", in: json) else { continue }
                        self.timer?.invalidate()
                        self.onToken(access, Self.find("refresh_token", in: json))
                        return
                    }
                }
            }
        }

        static func find(_ key: String, in json: Any) -> String? {
            if let dict = json as? [String: Any] {
                if let v = dict[key] as? String, !v.isEmpty { return v }
                for value in dict.values { if let v = find(key, in: value) { return v } }
            } else if let array = json as? [Any] {
                for value in array { if let v = find(key, in: value) { return v } }
            }
            return nil
        }
    }
}
