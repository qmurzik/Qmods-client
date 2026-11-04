import SwiftUI

/// Loads voiceovers → player sources → episodes for one release.
/// Shared by the release page (inline episode list) and the player (switching on the fly).
@MainActor
final class EpisodesModel: ObservableObject {
    @Published private(set) var types: [VoiceoverType] = []
    @Published private(set) var selectedType: VoiceoverType?
    @Published private(set) var sources: [EpisodeSource] = []
    @Published private(set) var selectedSource: EpisodeSource?
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loaded = false
    @Published var error: String?
    /// Dubs that offer a native (ad-free, fast) AniLibria/Liberty source.
    @Published private(set) var nativeTypeIds: Set<Int> = []

    nonisolated static func isNativeSource(_ s: EpisodeSource) -> Bool {
        let n = s.name.lowercased()
        return n.contains("libria") || n.contains("liberty") || n.contains("animelib")
    }

    enum Provider: String, CaseIterable, Identifiable {
        case anixart = "Anixart", animelib = "AnimeLib"
        var id: String { rawValue }
    }

    @Published private(set) var provider: Provider = .anixart
    @Published private(set) var libAnime: LibAnime?
    private var libEpisodes: [LibEpisode] = []
    /// teamId -> which players that team has (taken from the first episode).
    private var libTeamPlayers: [Int: (native: Bool, kodik: Bool)] = [:]
    private static let animeLibSourceId = 1
    private static let kodikSourceId = 2

    /// Dubs with a native source first, keeping the API order otherwise.
    var sortedTypes: [VoiceoverType] {
        types.filter { nativeTypeIds.contains($0.id) } + types.filter { !nativeTypeIds.contains($0.id) }
    }

    let releaseId: Int
    private let api = AnixartAPI.shared
    private var preferredTypeId: Int?
    private var preferredSourceId: Int?

    init(releaseId: Int) {
        self.releaseId = releaseId
    }

    func load(preferredTypeId: Int?, preferredSourceId: Int?) async {
        guard !isLoading else { return }
        self.preferredTypeId = preferredTypeId
        self.preferredSourceId = preferredSourceId
        isLoading = true
        error = nil
        do {
            types = try await api.voiceovers(releaseId: releaseId)
            isLoading = false
            scanNativeSources()
            let preferred = types.first { $0.id == preferredTypeId } ?? types.first
            if let preferred { await select(type: preferred) }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
        loaded = true
    }

    // MARK: Providers

    func switchProvider(_ p: Provider, release: Release) async {
        guard p != provider || (p == .animelib && libAnime == nil) else { return }
        provider = p
        types = []
        sources = []
        episodes = []
        selectedType = nil
        selectedSource = nil
        nativeTypeIds = []
        error = nil
        switch p {
        case .anixart:
            loaded = false
            await load(preferredTypeId: preferredTypeId, preferredSourceId: preferredSourceId)
        case .animelib:
            await loadAnimeLib(release: release)
        }
    }

    /// Re-reads AnimeLib (e.g. after signing in: their own player may only be listed for users).
    func reloadAnimeLib(release: Release) async {
        AnimeLibAPI.clearCache()
        libAnime = nil
        provider = .animelib
        types = []
        sources = []
        episodes = []
        nativeTypeIds = []
        await loadAnimeLib(release: release)
    }

    private func loadAnimeLib(release: Release) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let anime = try await AnimeLibAPI.match(release)
            libAnime = anime
            DebugLog.log("animelib: matched \(anime.slugURL)")
            libEpisodes = try await AnimeLibAPI.episodes(slugURL: anime.slugURL)
            guard let first = libEpisodes.first else { throw AnimeLibAPI.LibError.noVideo }
            let players = try await AnimeLibAPI.players(episodeId: first.id)
            var order: [LibTeam] = []
            libTeamPlayers = [:]
            for p in players {
                if !order.contains(p.team) { order.append(p.team) }
                var entry = libTeamPlayers[p.team.id] ?? (false, false)
                if p.isNative { entry.native = true }
                if p.player.lowercased() == "kodik" { entry.kodik = true }
                libTeamPlayers[p.team.id] = entry
            }
            nativeTypeIds = Set(libTeamPlayers.filter { $0.value.native }.map(\.key))
            types = order.map { VoiceoverType(id: $0.id, name: $0.name, isSub: $0.isSubtitles,
                                              episodesCount: libEpisodes.count) }
            guard provider == .animelib else { return }
            let preferred = types.first { nativeTypeIds.contains($0.id) } ?? types.first
            if let preferred { selectLibTeam(preferred) }
            if !AnimeLibSession.isLoggedIn && nativeTypeIds.isEmpty {
                DebugLog.log("animelib: no own player for guests")
            }
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func selectLibTeam(_ type: VoiceoverType) {
        selectedType = type
        let info = libTeamPlayers[type.id] ?? (false, true)
        var list: [EpisodeSource] = []
        if info.native { list.append(EpisodeSource(id: Self.animeLibSourceId, name: "AnimeLib")) }
        if info.kodik || !info.native { list.append(EpisodeSource(id: Self.kodikSourceId, name: "Kodik")) }
        sources = list
        selectLibSource(list[0])
    }

    private func selectLibSource(_ source: EpisodeSource) {
        guard let team = selectedType else { return }
        selectedSource = source
        let player = source.id == Self.animeLibSourceId ? "animelib" : "kodik"
        episodes = libEpisodes.enumerated().map { index, e in
            let position = Int(Double(e.number) ?? Double(index + 1))
            var title = "\(e.number) серия"
            if let n = e.name, !n.isEmpty, n != e.number { title += " · " + n }
            return Episode(position: position, releaseId: releaseId, sourceId: source.id, name: title,
                           url: "animelib://play?episode=\(e.id)&team=\(team.id)&player=\(player)")
        }
    }

    func select(type: VoiceoverType) async {
        if provider == .animelib {
            selectLibTeam(type)
            return
        }
        selectedType = type
        sources = []
        episodes = []
        selectedSource = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let s = try await api.sources(releaseId: releaseId, typeId: type.id)
            guard selectedType?.id == type.id else { return }
            sources = s
            if s.contains(where: Self.isNativeSource) { nativeTypeIds.insert(type.id) }
            // Prefer the last used player, then Libria/Liberty (native AVPlayer), then Kodik, then the first one.
            let preferred = s.first { $0.id == preferredSourceId }
                ?? s.first(where: Self.isNativeSource)
                ?? s.first { $0.name.localizedCaseInsensitiveContains("kodik") }
                ?? s.first
            if let preferred { await loadEpisodes(source: preferred) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Looks up the players of every dub in the background to mark the ad-free ones.
    private func scanNativeSources() {
        let ids = types.prefix(20).map(\.id)
        let releaseId = releaseId
        Task {
            await withTaskGroup(of: (Int, Bool).self) { group in
                for id in ids {
                    group.addTask {
                        let s = (try? await AnixartAPI.shared.sources(releaseId: releaseId, typeId: id)) ?? []
                        return (id, s.contains(where: EpisodesModel.isNativeSource))
                    }
                }
                for await (id, native) in group where native && provider == .anixart {
                    nativeTypeIds.insert(id)
                }
            }
        }
    }

    func select(source: EpisodeSource) async {
        if provider == .animelib {
            selectLibSource(source)
            return
        }
        isLoading = true
        defer { isLoading = false }
        await loadEpisodes(source: source)
    }

    private func loadEpisodes(source: EpisodeSource) async {
        guard let type = selectedType else { return }
        selectedSource = source
        episodes = []
        do {
            let e = try await api.episodes(releaseId: releaseId, typeId: type.id, sourceId: source.id)
            guard selectedSource?.id == source.id, selectedType?.id == type.id else { return }
            episodes = e
            // Resolve AniLibria streams in the background so the player starts immediately.
            if let first = e.first, first.isLibria, let url = first.playerURL {
                LibriaResolver.prefetch(url)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func episode(after ep: Episode) -> Episode? {
        guard let i = episodes.firstIndex(of: ep), i + 1 < episodes.count else { return nil }
        return episodes[i + 1]
    }

    func episode(before ep: Episode) -> Episode? {
        guard let i = episodes.firstIndex(of: ep), i > 0 else { return nil }
        return episodes[i - 1]
    }

    /// After switching dub/player, find the same episode number in the new list.
    func matching(_ ep: Episode) -> Episode? {
        episodes.first { $0.position == ep.position }
    }
}
