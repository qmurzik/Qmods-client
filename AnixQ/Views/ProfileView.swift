import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: HistoryStore
    @State private var showLogin = false
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                if auth.isLoggedIn {
                    HStack(spacing: 14) {
                        Text(String((auth.profileName ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 24, weight: .heavy))
                            .frame(width: 56, height: 56)
                            .background(Theme.accentGradient, in: Circle())
                        VStack(alignment: .leading) {
                            Text(auth.profileName ?? "Профиль").font(.headline)
                            Text("Аккаунт Anixart").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label("Войти в Anixart", systemImage: "person.badge.key")
                    }
                    Text("Вход нужен только для закладок и избранного — смотреть можно без аккаунта.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if auth.isLoggedIn {
                Section("Мои списки") {
                    NavigationLink {
                        RemoteListView(title: "Избранное") { page in
                            try await AnixartAPI.shared.favorites(page: page)
                        }
                    } label: {
                        Label("Избранное", systemImage: "heart")
                    }
                    ForEach(WatchList.allCases) { list in
                        NavigationLink {
                            RemoteListView(title: list.title) { page in
                                try await AnixartAPI.shared.list(list, page: page)
                            }
                        } label: {
                            Label(list.title, systemImage: list.icon)
                        }
                    }
                }
            }

            Section("История на устройстве") {
                if history.entries.isEmpty {
                    Text("Пока пусто — начните смотреть что-нибудь").foregroundStyle(.secondary)
                }
                ForEach(history.entries.prefix(50)) { entry in
                    NavigationLink(value: ReleaseRoute(id: entry.releaseId)) {
                        HStack(spacing: 12) {
                            RemoteImage(url: entry.image.flatMap(URL.init(string:)))
                                .frame(width: 44, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline).lineLimit(1)
                                Text("\(entry.episodeName) · \(entry.typeName)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(entry.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Удалить", role: .destructive) { history.remove(entry) }
                    }
                }
                if !history.entries.isEmpty {
                    Button("Очистить историю", role: .destructive) { confirmClear = true }
                }
            }

            if auth.isLoggedIn {
                Section {
                    Button("Выйти", role: .destructive) { auth.signOut() }
                }
            }

            Section {
                Text("AnixQ — неофициальный клиент. Каталог и видео предоставляются сервисом Anixart и его плеерами.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Профиль")
        .releaseDestinations()
        .sheet(isPresented: $showLogin) { LoginView() }
        .confirmationDialog("Очистить всю историю просмотра?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) { history.clear() }
        }
    }
}

struct RemoteListView: View {
    let title: String
    let fetcher: (Int) async throws -> Page<Release>

    @StateObject private var pager = PagedReleases()

    var body: some View {
        ScrollView {
            VStack {
                ReleaseGrid(releases: pager.items) { Task { await pager.loadMore() } }
                if pager.isLoading {
                    ProgressView().padding()
                } else if let error = pager.error {
                    ErrorView(message: error) { Task { await pager.reset(fetcher) } }
                } else if pager.items.isEmpty {
                    Text("Список пуст").foregroundStyle(.secondary).padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(title)
        .refreshable { await pager.reset(fetcher) }
        .task { if pager.items.isEmpty { await pager.reset(fetcher) } }
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var login = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Логин или e-mail", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Используйте аккаунт Anixart. Пароль отправляется только на сервер Anixart.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading { ProgressView() } else { Text("Войти").bold() }
                            Spacer()
                        }
                    }
                    .disabled(login.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle("Вход в Anixart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }

    private func submit() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await auth.signIn(login: login.trimmingCharacters(in: .whitespaces), password: password)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
