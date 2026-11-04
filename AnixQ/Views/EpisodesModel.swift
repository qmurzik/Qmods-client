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
            let preferred = types.first { $0.id == preferredTypeId } ?? types.first
            if let preferred { await select(type: preferred) }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
        loaded = true
    }

    func select(type: VoiceoverType) async {
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
            // Prefer the last used player, then Kodik (best compatibility), then the first one.
            let preferred = s.first { $0.id == preferredSourceId }
                ?? s.first { $0.name.localizedCaseInsensitiveContains("kodik") }
                ?? s.first
            if let preferred { await loadEpisodes(source: preferred) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func select(source: EpisodeSource) async {
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
