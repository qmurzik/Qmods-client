import SwiftUI

@MainActor
final class ReleaseModel: ObservableObject {
    @Published var release: Release?
    @Published var error: String?
    @Published var isFavorite = false
    @Published var listStatus: Int?
    @Published var actionError: String?

    let releaseId: Int
    private let api = AnixartAPI.shared

    init(releaseId: Int) { self.releaseId = releaseId }

    func load() async {
        error = nil
        do {
            let r = try await api.release(releaseId)
            release = r
            isFavorite = r.isFavorite
            listStatus = (r.profileListStatus ?? 0) > 0 ? r.profileListStatus : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleFavorite() async {
        let target = !isFavorite
        isFavorite = target
        do {
            if target { try await api.addFavorite(releaseId: releaseId) }
            else { try await api.removeFavorite(releaseId: releaseId) }
        } catch {
            isFavorite = !target
            actionError = error.localizedDescription
        }
    }

    func setList(_ list: WatchList?) async {
        let previous = listStatus
        listStatus = list?.rawValue
        do {
            if let list {
                try await api.addToList(list, releaseId: releaseId)
            } else if let current = previous.flatMap(WatchList.init(rawValue:)) {
                try await api.removeFromList(current, releaseId: releaseId)
            }
        } catch {
            listStatus = previous
            actionError = error.localizedDescription
        }
    }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case episodes = "Серии", about = "О тайтле", similar = "Похожие"
    var id: String { rawValue }
}

struct ReleaseDetailView: View {
    @StateObject private var model: ReleaseModel
    @StateObject private var episodes: EpisodesModel
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: HistoryStore
    @State private var expanded = false
    @State private var showLogin = false
    @State private var tab: DetailTab = .episodes
    @State private var playing: PlayerItem?
    @State private var showDubs = false

    init(releaseId: Int) {
        _model = StateObject(wrappedValue: ReleaseModel(releaseId: releaseId))
        _episodes = StateObject(wrappedValue: EpisodesModel(releaseId: releaseId))
    }

    var body: some View {
        Group {
            if let release = model.release {
                content(release)
            } else if let error = model.error {
                ErrorView(message: error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.release == nil { await model.load() }
            if !episodes.loaded {
                let last = history.last(for: model.releaseId)
                await episodes.load(preferredTypeId: last?.typeId, preferredSourceId: last?.sourceId)
            }
        }
        .sheet(isPresented: $showLogin) { LoginView() }
        .fullScreenCover(item: $playing) { item in
            PlayerView(release: item.release, start: item.episode, model: episodes)
        }
        .alert("Ошибка", isPresented: Binding(get: { model.actionError != nil },
                                              set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ r: Release) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backdrop(r)
                VStack(alignment: .leading, spacing: 18) {
                    actions(r)
                    Picker("Раздел", selection: $tab) {
                        ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .episodes: episodesSection(r)
                    case .about: aboutSection(r)
                    case .similar: similarSection(r)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
    }

    private func backdrop(_ r: Release) -> some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: r.imageURL)
                .frame(height: 470)
                .blur(radius: 26)
                .overlay(Color.black.opacity(0.35))
                .clipped()
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Theme.background.opacity(0.6), location: 0.6),
                .init(color: Theme.background, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 14) {
                Poster(url: r.imageURL, radius: 16)
                    .frame(width: 150)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
                VStack(spacing: 4) {
                    Text(r.title)
                        .font(.system(size: 22, weight: .heavy))
                        .multilineTextAlignment(.center)
                    if let o = r.titleOriginal {
                        Text(o).font(.footnote).foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let g = r.grade, g > 0 { GradeBadge(grade: g) }
                        if let y = r.year { Pill(text: y) }
                        if let c = r.category?.name { Pill(text: c) }
                        if let s = r.status?.name { Pill(text: s) }
                        Pill(text: r.episodesText)
                        if let a = r.ageText { Pill(text: a) }
                    }
                    .padding(.horizontal)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 12)
        }
        .frame(height: 470)
    }

    private func actions(_ r: Release) -> some View {
        VStack(spacing: 12) {
            Button {
                startPlayback()
            } label: {
                HStack(spacing: 8) {
                    if episodes.isLoading && episodes.episodes.isEmpty {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(playTitle(r))
                }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(r.isPlayDisabled || episodes.episodes.isEmpty)
            .opacity(r.isPlayDisabled || episodes.episodes.isEmpty ? 0.6 : 1)

            HStack(spacing: 10) {
                Menu {
                    ForEach(WatchList.allCases) { list in
                        Button {
                            Task { await model.setList(list) }
                        } label: {
                            Label(list.title, systemImage: model.listStatus == list.rawValue ? "checkmark" : list.icon)
                        }
                    }
                    if model.listStatus != nil {
                        Button("Убрать из списков", role: .destructive) {
                            Task { await model.setList(nil) }
                        }
                    }
                } label: {
                    secondaryButton(model.listStatus.flatMap(WatchList.init(rawValue:))?.title ?? "В список",
                                    icon: model.listStatus == nil ? "bookmark" : "bookmark.fill",
                                    active: model.listStatus != nil)
                }
                .disabled(!auth.isLoggedIn)

                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    secondaryButton("Избранное", icon: model.isFavorite ? "heart.fill" : "heart",
                                    active: model.isFavorite)
                }
                .disabled(!auth.isLoggedIn)

                ShareLink(item: URL(string: "https://anixart.tv/release/\(r.id)")!) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 44)
                        .cardStyle(radius: 12)
                        .foregroundStyle(.white)
                }
            }
            if !auth.isLoggedIn {
                Button("Войдите в Anixart, чтобы добавлять в списки и избранное") { showLogin = true }
                    .font(.caption)
            }
            if r.isPlayDisabled {
                Text("Просмотр этого релиза недоступен в вашем регионе")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func secondaryButton(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(active ? Theme.accent : .white)
            Text(title).lineLimit(1)
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .cardStyle(radius: 12)
        .foregroundStyle(.white)
    }

    // MARK: Episodes

    @ViewBuilder
    private func episodesSection(_ r: Release) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !episodes.types.isEmpty {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(episodes.sortedTypes) { t in
                            Button {
                                Task { await episodes.select(type: t) }
                            } label: {
                                Label(dubTitle(t),
                                      systemImage: t.id == episodes.selectedType?.id ? "checkmark"
                                                   : (t.isSub ? "captions.bubble" : "mic"))
                            }
                        }
                    } label: {
                        selector(title: "Озвучка", value: episodes.selectedType?.name ?? "—")
                    }
                    if episodes.sources.count > 1 {
                        Menu {
                            ForEach(episodes.sources) { s in
                                Button {
                                    Task { await episodes.select(source: s) }
                                } label: {
                                    Label(EpisodesModel.isNativeSource(s) ? "⚡ \(s.name) · без рекламы" : "\(s.name) · с рекламой",
                                          systemImage: s.id == episodes.selectedSource?.id ? "checkmark" : "play.rectangle")
                                }
                            }
                        } label: {
                            selector(title: "Плеер", value: episodes.selectedSource?.name ?? "—")
                        }
                    }
                }
            }

            if episodes.isLoading && episodes.episodes.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if let error = episodes.error, episodes.episodes.isEmpty {
                ErrorView(message: error) {
                    Task { await episodes.load(preferredTypeId: nil, preferredSourceId: nil) }
                }
            } else if episodes.episodes.isEmpty {
                EmptyStateView(icon: "film.stack", text: "Серий пока нет")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(episodes.episodes) { ep in
                        episodeRow(ep, release: r)
                    }
                }
            }
        }
    }

    private func selector(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.secondaryText)
            HStack {
                Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .cardStyle(radius: 12)
        .foregroundStyle(.white)
    }

    private func episodeRow(_ ep: Episode, release r: Release) -> some View {
        let watched = history.isWatched(releaseId: r.id, position: ep.position)
        let isLast = history.last(for: r.id)?.episodePosition == ep.position
        return Button {
            playing = PlayerItem(release: r, episode: ep)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isLast ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.cardHighlight))
                    Text("\(ep.position)").font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ep.name).font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        if isLast { Text("Вы остановились здесь").foregroundStyle(Theme.accent) }
                        else if watched { Text("Просмотрено") }
                        if ep.isFiller { Text("· филлер") }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: watched ? "checkmark.circle.fill" : "play.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(watched ? Theme.secondaryText : Theme.accent)
            }
            .padding(10)
            .cardStyle(radius: 14)
            .opacity(watched && !isLast ? 0.7 : 1)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(watched ? "Отметить непросмотренной" : "Отметить просмотренной") {
                history.toggleWatched(releaseId: r.id, position: ep.position)
            }
        }
    }

    // MARK: About

    @ViewBuilder
    private func aboutSection(_ r: Release) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let note = r.note, !note.isEmpty {
                Text(note.strippingHTML)
                    .font(.footnote)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if let d = r.description, !d.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(d).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(expanded ? nil : 6)
                        .lineSpacing(3)
                    Button(expanded ? "Свернуть" : "Читать полностью") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if let genres = r.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres.components(separatedBy: ", "), id: \.self) { g in
                            NavigationLink(value: GenreRoute(name: g)) { Pill(text: g.capitalized) }
                        }
                    }
                }
            }
            infoTable(r)
            if !r.screenshotImages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Кадры").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(r.screenshotImages, id: \.self) { s in
                                RemoteImage(url: URL(string: s))
                                    .frame(width: 240, height: 135)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    private func infoTable(_ r: Release) -> some View {
        let rows: [(String, String?)] = [
            ("Студия", r.studio),
            ("Страна", r.country),
            ("Сезон", [r.seasonText, r.year].compactMap { $0 }.joined(separator: " ").nilIfEmpty),
            ("Длительность", r.duration.map { "\($0) мин." }),
            ("Режиссёр", r.director),
            ("Автор", r.author),
            ("Первоисточник", r.source),
            ("Озвучка", r.translators)
        ]
        let visible = rows.filter { ($0.1 ?? "").isEmpty == false }
        return VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0).foregroundStyle(Theme.secondaryText).frame(width: 120, alignment: .leading)
                    Text(row.1 ?? "").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 14))
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                if index < visible.count - 1 { Divider().overlay(Theme.stroke) }
            }
        }
        .cardStyle(radius: 14)
    }

    // MARK: Similar

    @ViewBuilder
    private func similarSection(_ r: Release) -> some View {
        let related = r.related.filter { $0.id != r.id }
        VStack(alignment: .leading, spacing: 16) {
            if !related.isEmpty {
                Text("Связанные").font(.headline)
                ReleaseGrid(releases: related)
            }
            if !r.recommended.isEmpty {
                Text("Рекомендации").font(.headline)
                ReleaseGrid(releases: r.recommended)
            }
            if related.isEmpty && r.recommended.isEmpty {
                EmptyStateView(icon: "rectangle.stack", text: "Похожих тайтлов нет")
            }
        }
    }

    // MARK: Helpers

    private func dubTitle(_ t: VoiceoverType) -> String {
        var title = t.name
        if let n = t.episodesCount { title += " · " + String(n) + " эп." }
        if episodes.nativeTypeIds.contains(t.id) { title = "⚡ " + title + " · без рекламы" }
        return title
    }

    private func playTitle(_ r: Release) -> String {
        if let last = history.last(for: r.id) { return "Продолжить · \(last.episodeName)" }
        return "Смотреть 1 серию"
    }

    private func startPlayback() {
        guard let r = model.release else { return }
        let last = history.last(for: r.id)
        let ep = last.flatMap { l in episodes.episodes.first { $0.position == l.episodePosition } }
            ?? episodes.episodes.first
        if let ep { playing = PlayerItem(release: r, episode: ep) }
    }
}

struct PlayerItem: Identifiable {
    let release: Release
    let episode: Episode
    var id: String { episode.url }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var strippingHTML: String {
        replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
