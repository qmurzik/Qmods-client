import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showSettings = false
    @State private var showLibLogin = false

    var body: some View {
        List {
            if !LibSession.isLoggedIn {
                Section {
                    Button { showLibLogin = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Войти в AnimeLib").foregroundStyle(.primary)
                                Text("Плеер без рекламы и синхронизация закладок")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                    }
                }
            }

            if let p = library.shikiImport {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Загружаем список Shikimori: \(p.done) из \(p.total)").font(.subheadline)
                        ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    }
                }
            } else if let summary = library.shikiImportSummary {
                Section { Label(summary, systemImage: "checkmark.circle").font(.footnote) }
            }

            if let e = library.lastSyncError {
                Section { Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
            }

            Section("Закладки") {
                ForEach(BookmarkStatus.allCases) { s in
                    NavigationLink {
                        BookmarkFolderView(status: s)
                    } label: {
                        HStack {
                            Label(s.title, systemImage: s.icon)
                            Spacer()
                            Text("\(library.titles(in: s).count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if library.history.isEmpty {
                    Text("Здесь появятся тайтлы, которые вы начнёте смотреть").foregroundStyle(.secondary)
                }
                ForEach(library.history.prefix(30)) { entry in
                    NavigationLink(value: entry.title) {
                        HStack(spacing: 12) {
                            PosterImage(url: entry.title.thumbURL, radius: 6).frame(width: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("Серия \(entry.episodeNumber) · \(entry.teamName)").font(.caption).foregroundStyle(.secondary)
                                ProgressView(value: entry.progress).tint(Theme.accent)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { library.removeFromHistory(entry) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("История")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Медиатека")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if library.isSyncing { ProgressView() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLibLogin) {
            LibLoginView { ok in if ok { Task { await library.syncBookmarks() } } }
        }
        .appDestinations()
        .refreshable {
            await library.syncBookmarks()
            await library.importShikimori()
        }
    }
}

struct BookmarkFolderView: View {
    let status: BookmarkStatus
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            let titles = library.titles(in: status)
            if titles.isEmpty {
                EmptyState(icon: status.icon, title: "Пусто", subtitle: "Добавляйте тайтлы кнопкой «+» на их странице")
            } else {
                PosterGrid(titles: titles).padding()
            }
        }
        .navigationTitle(status.title)
        .refreshable { await library.syncBookmarks() }
    }
}

// MARK: - Settings

struct PlayerPrefs {
    static var autoSkipOpening: Bool {
        get { UserDefaults.standard.object(forKey: "player.autoSkip") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "player.autoSkip") }
    }
    static var autoNext: Bool {
        get { UserDefaults.standard.object(forKey: "player.autoNext") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "player.autoNext") }
    }
    static var openingLength: Double {
        get { UserDefaults.standard.object(forKey: "player.opLength") as? Double ?? 85 }
        set { UserDefaults.standard.set(newValue, forKey: "player.opLength") }
    }
    static var preferredHeight: Int {
        get { UserDefaults.standard.object(forKey: "player.quality") as? Int ?? 720 }
        set { UserDefaults.standard.set(newValue, forKey: "player.quality") }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var shiki = ShikiSync.shared
    @State private var libLoggedIn = LibSession.isLoggedIn
    @State private var showLibLogin = false
    @State private var showShikiLogin = false
    @State private var notify = EpisodeNotifier.isEnabled
    @State private var autoSkip = PlayerPrefs.autoSkipOpening
    @State private var autoNext = PlayerPrefs.autoNext
    @State private var opLength = PlayerPrefs.openingLength
    @State private var quality = PlayerPrefs.preferredHeight
    @AppStorage("adblock") private var adblock = true
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if libLoggedIn {
                        LabeledContent("AnimeLib", value: LibSession.username ?? "вход выполнен")
                        Button("Синхронизировать закладки") { Task { await library.syncBookmarks() } }
                        Button("Выйти из AnimeLib", role: .destructive) {
                            LibSession.clear()
                            LibAPI.clearCache()
                            libLoggedIn = false
                        }
                    } else {
                        Button("Войти в AnimeLib") { showLibLogin = true }
                    }
                    if shiki.isLoggedIn {
                        LabeledContent("Shikimori", value: ShikiSession.nickname ?? "вход выполнен")
                        Button(library.shikiImport == nil ? "Загрузить мой список с Shikimori" : "Загружаем список…") {
                            Task { await library.importShikimori() }
                        }
                        .disabled(library.shikiImport != nil)
                        Button("Выйти из Shikimori", role: .destructive) {
                            ShikiSession.clear()
                            shiki.refreshState()
                        }
                    } else {
                        Button("Подключить Shikimori") { showShikiLogin = true }
                    }
                } header: {
                    Text("Аккаунты")
                } footer: {
                    Text("Shikimori: просто войдите на сайте — просмотренные серии, статусы и оценки будут отмечаться автоматически.")
                }

                Section {
                    Toggle("Уведомлять о новых сериях", isOn: $notify)
                        .onChange(of: notify) { on in
                            Task {
                                if on { notify = await EpisodeNotifier.enable() } else { EpisodeNotifier.isEnabled = false }
                                await EpisodeNotifier.reschedule(titles: library.watchingTitles)
                            }
                        }
                } footer: {
                    Text("Для тайтлов из «Смотрю» — по расписанию Shikimori, с запасом 2 часа на озвучку.")
                }

                Section("Плеер") {
                    Toggle("Следующая серия автоматически", isOn: $autoNext)
                        .onChange(of: autoNext) { PlayerPrefs.autoNext = $0 }
                    Toggle("Пропускать опенинг автоматически", isOn: $autoSkip)
                        .onChange(of: autoSkip) { PlayerPrefs.autoSkipOpening = $0 }
                    Stepper("Длина опенинга: \(Int(opLength)) с", value: $opLength, in: 30...150, step: 5)
                        .onChange(of: opLength) { PlayerPrefs.openingLength = $0 }
                    Picker("Качество по умолчанию", selection: $quality) {
                        Text("1080p").tag(1080)
                        Text("720p").tag(720)
                        Text("480p").tag(480)
                        Text("360p").tag(360)
                    }
                    .onChange(of: quality) { PlayerPrefs.preferredHeight = $0 }
                    Toggle("Блокировать рекламу в Kodik", isOn: $adblock)
                }

                Section("Данные") {
                    NavigationLink("Диагностика плеера") { DiagnosticsView() }
                    Button("Очистить историю просмотра", role: .destructive) { confirmClear = true }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .sheet(isPresented: $showLibLogin) {
                LibLoginView { ok in
                    libLoggedIn = LibSession.isLoggedIn
                    if ok { Task { await library.syncBookmarks() } }
                }
            }
            .sheet(isPresented: $showShikiLogin) {
                ShikiLoginView { Task { await library.importShikimori() } }
            }
            .confirmationDialog("Очистить историю и прогресс?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { library.clearHistory() }
            }
        }
    }
}

struct DiagnosticsView: View {
    @State private var text = ""
    @State private var crash = CrashReporter.lastReport

    var body: some View {
        List {
            if let crash {
                Section {
                    Text(crash)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                    ShareLink(item: crash) { Label("Отправить отчёт о сбое", systemImage: "square.and.arrow.up") }
                    Button("Удалить отчёт", role: .destructive) {
                        CrashReporter.clear()
                        self.crash = nil
                    }
                } header: {
                    Text("Последний сбой")
                }
            }
            Section("Журнал этого запуска") {
                Text(text.isEmpty ? "Пусто — откройте серию и вернитесь сюда." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Диагностика")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: text.isEmpty ? "empty" : text) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onAppear { text = DebugLog.read() }
        .refreshable { text = DebugLog.read() }
    }
}
