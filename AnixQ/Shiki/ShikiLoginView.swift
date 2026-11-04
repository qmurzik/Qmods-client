import SwiftUI
import WebKit

/// Shikimori sign-in: one-time app registration (Shikimori requires a client id/secret),
/// then the standard OAuth page; the authorization code is picked up automatically.
struct ShikiLoginView: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var clientId = ShikiSession.clientId ?? ""
    @State private var clientSecret = ShikiSession.clientSecret ?? ""
    @State private var appName = ShikiSession.appName
    @State private var showAuth = false
    @State private var status: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Откройте shikimori.io → Настройки → Приложения → «Новое приложение».", systemImage: "1.circle")
                    Label("Название — любое (например, AnixQ). Redirect URI:", systemImage: "2.circle")
                    HStack {
                        Text(ShikiSession.redirectURI).font(.system(.footnote, design: .monospaced))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = ShikiSession.redirectURI
                            status = "Redirect URI скопирован"
                        } label: { Image(systemName: "doc.on.doc") }
                    }
                    Label("Отметьте доступ user_rates, сохраните и вставьте Client ID и Client Secret ниже.", systemImage: "3.circle")
                    Button {
                        openURL(URL(string: "\(ShikiAPI.host)/oauth/applications/new")!)
                    } label: {
                        Label("Открыть страницу приложений", systemImage: "safari")
                    }
                } header: {
                    Text("Один раз: регистрация приложения")
                } footer: {
                    Text("Shikimori выдаёт доступ только зарегистрированным приложениям. Это бесплатно и занимает минуту; данные хранятся только на этом устройстве.")
                }

                Section("Данные приложения") {
                    TextField("Название приложения", text: $appName)
                        .autocorrectionDisabled()
                    TextField("Client ID", text: $clientId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    SecureField("Client Secret", text: $clientSecret)
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    Button {
                        ShikiSession.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
                        ShikiSession.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                        ShikiSession.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "AnixQ"
                        showAuth = true
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Войти через Shikimori").bold() }
                            Spacer()
                        }
                    }
                    .disabled(clientId.isEmpty || clientSecret.isEmpty || working)
                } footer: {
                    if let status { Text(status) }
                }
            }
            .navigationTitle("Shikimori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .sheet(isPresented: $showAuth) {
                NavigationStack {
                    ShikiAuthWebView { code in
                        showAuth = false
                        Task { await finish(code: code) }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Авторизация")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showAuth = false } }
                    }
                }
            }
        }
    }

    private func finish(code: String) async {
        working = true
        defer { working = false }
        do {
            try await ShikiAPI.exchange(code: code)
            ShikiSync.shared.refreshState()
            onDone()
            dismiss()
        } catch {
            status = "Не удалось войти: \(error.localizedDescription). Проверьте Client ID / Secret и Redirect URI."
        }
    }
}

private struct ShikiAuthWebView: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        if let url = ShikiAPI.authorizeURL() { web.load(URLRequest(url: url)) }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        /// With the out-of-band redirect, Shikimori shows the code at /oauth/authorize/<code>.
        private func check(_ url: URL?) {
            guard !done, let url else { return }
            let parts = url.path.split(separator: "/")
            if parts.count == 3, parts[0] == "oauth", parts[1] == "authorize" {
                done = true
                onCode(String(parts[2]))
            } else if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value, url.path.contains("oauth") {
                done = true
                onCode(code)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            check(navigationAction.request.url)
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.url)
        }
    }
}
