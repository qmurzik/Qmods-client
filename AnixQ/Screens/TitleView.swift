import SwiftUI

struct TeamOption: Identifiable, Hashable {
    let team: LibTeam
    var native: Bool
    var kodik: Bool
    var id: Int { team.id }
}

struct PlayRequest: Identifiable {
    let episodeIndex: Int
    let team: TeamOption
    let id = UUID()
}

@MainActor
final class TitleModel: ObservableObject {
    let title: Title
    @Published var detail: TitleDetail?
    @Published var episodes: [LibEpisode] = []
    @Published var teams: [TeamOption] = []
    @Published var selectedTeam: TeamOption?
    @Published var related: [RelatedTitle] = []
    @Published var similar: [Title] = []
    @Published var shiki: ShikiAnimeInfo?
    @Published var loadingEpisodes = true
    @Published var error: String?

    static var preferredTeamName: String? {
        get { UserDefaults.standard.string(forKey: "preferredTeam") }
        set { UserDefaults.standard.set(newValue, forKey: "preferredTeam") }
    }

    init(title: Title) { self.title = title }

    var displayTitle: Title { detail?.title ?? title }

    func load(lastTeamId: Int?) async {
        let slug = title.slugURL
        async let d = try? LibAPI.detail(slug)
        async let r = LibAPI.related(slug)
        async let s = LibAPI.similar(slug)
        await loadEpisodes(lastTeamId: lastTeamId)
        detail = await d
        related = await r
        similar = await s
        if let sid = (detail?.title ?? title).shikiId { shiki = try? await ShikiAPI.anime(sid) }
    }

    func loadEpisodes(lastTeamId: Int?) async {
        loadingEpisodes = true
        defer { loadingEpisodes = false }
        do {
            episodes = try await LibAPI.episodes(slug: title.slugURL)
            guard let first = episodes.first else { return }
            // Teams can differ between early and recent episodes, so look at both ends.
            let firstId = first.id
            let lastId: Int? = episodes.count > 1 ? episodes[episodes.count - 1].id : nil
            async let a = LibAPI.players(episodeId: firstId)
            async let b = Self.players(lastId)
            let players = (try await a) + (await b)
            var order: [TeamOption] = []
            for p in players {
                if let i = order.firstIndex(where: { $0.team.id == p.team.id }) {
                    order[i].native = order[i].native || p.isNative
                    order[i].kodik = order[i].kodik || p.isKodik
                } else {
                    order.append(TeamOption(team: p.team, native: p.isNative, kodik: p.isKodik))
                }
            }
            // Ad-free first, then dubs before subtitles.
            teams = order.filter { $0.native && !$0.team.isSubtitles } + order.filter { $0.native && $0.team.isSubtitles }
                + order.filter { !$0.native }
            selectedTeam = teams.first { $0.id == lastTeamId }
                ?? teams.first { $0.team.name == Self.preferredTeamName && $0.native }
                ?? teams.first
            if let t = selectedTeam, t.native { LibAPI.warmUp(episodeId: first.id, teamId: t.id) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func players(_ id: Int?) async -> [LibPlayer] {
        guard let id else { return [] }
        return (try? await LibAPI.players(episodeId: id)) ?? []
    }

    func select(_ team: TeamOption) {
        selectedTeam = team
        Self.preferredTeamName = team.team.name
        if team.native, let e = episodes.first { LibAPI.warmUp(episodeId: e.id, teamId: team.id) }
    }
}

struct TitleView: View {
    @StateObject private var model: TitleModel
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var shikiSync = ShikiSync.shared
    @State private var play: PlayRequest?
    @State private var expanded = false
    @State private var showAllEpisodes = false

    init(title: Title) {
        _model = StateObject(wrappedValue: TitleModel(title: title))
    }

    private var t: Title { model.displayTitle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                VStack(alignment: .leading, spacing: 26) {
                    if let summary = model.detail?.summary { about(summary) }
                    episodesSection
                    infoSection
                }
                relatedSection
                Shelf(title: "Похожие", titles: model.similar)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: URL(string: "https://anilib.me/ru/anime/\(t.slugURL)")!) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task { if model.episodes.isEmpty { await model.load(lastTeamId: library.lastEntry(titleId: t.id)?.teamId) } }
        .fullScreenCover(item: $play) { req in
            PlayerScreen(title: t, background: model.detail?.backgroundURL, episodes: model.episodes,
                         teams: model.teams, startIndex: req.episodeIndex, team: req.team)
        }
        .sheet(isPresented: $showAllEpisodes) { allEpisodesSheet }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: model.detail?.backgroundURL ?? t.coverURL)
                .frame(height: 520)
                .frame(maxWidth: .infinity)
                .blur(radius: model.detail?.backgroundURL == nil ? 18 : 0)
                .clipped()
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: Theme.background.opacity(0.8), location: 0.72),
                .init(color: Theme.background, location: 1)
            ], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 10) {
                if model.detail?.backgroundURL == nil {
                    PosterImage(url: t.coverURL, radius: 12).frame(width: 130).shadow(radius: 16)
                }
                Text(t.title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text(metaLine).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                playButtons.padding(.horizontal).padding(.top, 6)
            }
            .padding(.bottom, 8)
        }
        .frame(height: 520)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let s = t.score { parts.append("★ " + String(format: "%.1f", s)) }
        if let type = t.typeLabel { parts.append(type) }
        if let y = t.year { parts.append(String(y)) }
        if !model.episodes.isEmpty { parts.append("\(model.episodes.count) эп.") }
        if let a = t.age { parts.append(a) }
        if let g = model.detail?.genres.prefix(2).map(\.name), !g.isEmpty { parts.append(g.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private var nextEpisodeIndex: Int {
        guard !model.episodes.isEmpty else { return 0 }
        if let last = library.lastEntry(titleId: t.id),
           let i = model.episodes.firstIndex(where: { $0.id == last.episodeId }) {
            if last.progress > 0.92, i + 1 < model.episodes.count { return i + 1 }
            return i
        }
        return model.episodes.firstIndex { !library.isWatched(titleId: t.id, number: $0.number) } ?? 0
    }

    private var playButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let team = model.selectedTeam { play = PlayRequest(episodeIndex: nextEpisodeIndex, team: team) }
                } label: {
                    HStack(spacing: 8) {
                        if model.loadingEpisodes { ProgressView().tint(.black) } else { Image(systemName: "play.fill") }
                        Text(playLabel)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.selectedTeam == nil)

                BookmarkMenu(title: t) {
                    Image(systemName: library.bookmark(for: t.slugURL) == nil ? "plus" : "checkmark")
                }
                .buttonStyle(GlassButtonStyle())
                .frame(width: 50)
            }
            if let b = library.bookmark(for: t.slugURL) {
                Label(b.title, systemImage: b.icon).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var playLabel: String {
        guard !model.episodes.isEmpty else { return model.loadingEpisodes ? "Загрузка" : "Нет серий" }
        let ep = model.episodes[nextEpisodeIndex]
        if library.resumePosition(episodeId: ep.id) != nil { return "Продолжить · серия \(ep.number)" }
        return model.episodes.count == 1 ? "Смотреть" : "Смотреть · серия \(ep.number)"
    }

    // MARK: About

    private func about(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 4)
            Button(expanded ? "Свернуть" : "Ещё") { withAnimation { expanded.toggle() } }
                .font(.subheadline.weight(.semibold))
            if let genres = model.detail?.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres) { g in
                            NavigationLink(value: GenreRoute(genre: g)) {
                                Text(g.name).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Episodes

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Серии") {
                if model.episodes.count > 6 {
                    Button("Все \(model.episodes.count)") { showAllEpisodes = true }.font(.subheadline)
                }
            }
            if !model.teams.isEmpty { teamPicker.padding(.horizontal) }

            if model.loadingEpisodes && model.episodes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if model.episodes.isEmpty {
                Text(model.error ?? "Серий пока нет").foregroundStyle(.secondary).padding(.horizontal)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(Array(model.episodes.enumerated()), id: \.element.id) { i, ep in
                                Button {
                                    if let team = model.selectedTeam { play = PlayRequest(episodeIndex: i, team: team) }
                                } label: {
                                    EpisodeCard(episode: ep, image: model.detail?.backgroundURL ?? t.coverURL,
                                                progress: library.progress(episodeId: ep.id),
                                                watched: library.isWatched(titleId: t.id, number: ep.number))
                                }
                                .buttonStyle(PressableStyle())
                                .id(i)
                                .contextMenu { watchedToggle(ep) }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onAppear { proxy.scrollTo(nextEpisodeIndex, anchor: .leading) }
                    .onChange(of: model.episodes.count) { _ in proxy.scrollTo(nextEpisodeIndex, anchor: .leading) }
                }
            }
        }
    }

    private func watchedToggle(_ ep: LibEpisode) -> some View {
        let watched = library.isWatched(titleId: t.id, number: ep.number)
        return Button {
            library.toggleWatched(title: t, number: ep.number)
        } label: {
            Label(watched ? "Не просмотрено" : "Просмотрено", systemImage: watched ? "eye.slash" : "eye")
        }
    }

    private var teamPicker: some View {
        Menu {
            ForEach(model.teams) { o in
                Button {
                    model.select(o)
                } label: {
                    Label(teamLabel(o), systemImage: o.id == model.selectedTeam?.id ? "checkmark"
                          : (o.team.isSubtitles ? "captions.bubble" : "waveform"))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.selectedTeam?.team.isSubtitles == true ? "captions.bubble.fill" : "waveform")
                Text(model.selectedTeam.map(teamLabel) ?? "Озвучка").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: Capsule())
        }
        .foregroundStyle(.primary)
    }

    private func teamLabel(_ o: TeamOption) -> String {
        (o.native ? "⚡ " : "") + o.team.name + (o.native ? "" : " · Kodik, реклама")
    }

    private var allEpisodesSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(model.episodes.enumerated()), id: \.element.id) { i, ep in
                    Button {
                        showAllEpisodes = false
                        if let team = model.selectedTeam {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                play = PlayRequest(episodeIndex: i, team: team)
                            }
                        }
                    } label: {
                        HStack {
                            Text(ep.number).font(.headline.monospacedDigit()).frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ep.displayTitle).foregroundStyle(.primary)
                                let p = library.progress(episodeId: ep.id)
                                if p > 0.02 { ProgressView(value: p).tint(Theme.accent) }
                            }
                            Spacer()
                            if library.isWatched(titleId: t.id, number: ep.number) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions { watchedToggle(ep).tint(.gray) }
                }
            }
            .navigationTitle("Серии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showAllEpisodes = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Информация")
            VStack(spacing: 0) {
                ForEach(infoRows, id: \.0) { row in
                    HStack(alignment: .top) {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(row.1).multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 10)
                    if row.0 != infoRows.last?.0 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .cardStyle()
            .padding(.horizontal)

            if ShikiSession.isLoggedIn, t.shikiId != nil {
                Menu {
                    ForEach((1...10).reversed(), id: \.self) { n in
                        Button("\(n)") { Task { await shikiSync.rate(title: t, score: n) } }
                    }
                } label: {
                    Label("Оценить на Shikimori", systemImage: "star.leadinghalf.filled")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal)
            }
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let o = t.originalTitle { rows.append(("Оригинал", o)) }
        if let s = model.detail?.studios.first { rows.append(("Студия", s)) }
        if let d = model.detail?.duration { rows.append(("Длительность", d)) }
        if let s = t.statusLabel { rows.append(("Статус", s)) }
        if let at = model.shiki?.nextEpisodeAt {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMMM, HH:mm"
            rows.append(("Следующая серия", f.string(from: at)))
        }
        if let r = t.rating, r > 0 { rows.append(("AnimeLib", String(format: "%.2f · %d голосов", r, t.votes ?? 0))) }
        if let s = model.shiki?.score ?? t.shikiRate, s > 0 { rows.append(("Shikimori", String(format: "%.2f", s))) }
        if let v = model.detail?.views { rows.append(("Просмотры", v)) }
        if let a = model.detail?.authors.first { rows.append(("Автор", a)) }
        return rows
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !model.related.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Связанные")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(model.related) { r in
                            NavigationLink(value: r.title) {
                                VStack(alignment: .leading, spacing: 4) {
                                    PosterCard(title: r.title, showMeta: false)
                                    Text(r.relation).font(.caption2).foregroundStyle(Theme.accent)
                                }
                                .frame(width: 118)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct EpisodeCard: View {
    let episode: LibEpisode
    let image: URL?
    let progress: Double
    let watched: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: image)
                    .overlay(Color.black.opacity(watched ? 0.55 : 0.3))
                Text(episode.number)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                if progress > 0.02 && progress < 0.95 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.3))
                                Rectangle().fill(.white).frame(width: geo.size.width * progress)
                            }
                            .frame(height: 3)
                        }
                    }
                }
            }
            .frame(width: 200, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.accent)
                        .padding(6)
                }
            }
            Text(episode.displayTitle).font(.footnote.weight(.semibold)).lineLimit(1)
                .foregroundStyle(watched ? .secondary : .primary)
        }
        .frame(width: 200, alignment: .leading)
    }
}
