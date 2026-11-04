import SwiftUI

/// Step 1: choose a voiceover (dub / subtitles) and the player source, then show episodes.
struct VoiceoverPickerView: View {
    let release: Release

    @EnvironmentObject private var history: HistoryStore
    @State private var types: [VoiceoverType] = []
    @State private var selectedType: VoiceoverType?
    @State private var sources: [EpisodeSource] = []
    @State private var selectedSource: EpisodeSource?
    @State private var episodes: [Episode] = []
    @State private var error: String?
    @State private var isLoading = false
    @State private var playing: PlayerItem?

    private let api = AnixartAPI.shared
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !types.isEmpty {
                    sectionTitle("Озвучка")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(types) { t in
                                chip(title: t.name, subtitle: t.episodesCount.map { "\($0) эп." },
                                     selected: t.id == selectedType?.id, icon: t.isSub ? "captions.bubble" : "mic") {
                                    Task { await select(type: t) }
                                }
                            }
                        }
                    }
                }

                if sources.count > 1 {
                    sectionTitle("Плеер")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sources) { s in
                                chip(title: s.name, subtitle: s.episodesCount.map { "\($0) эп." },
                                     selected: s.id == selectedSource?.id, icon: "play.rectangle") {
                                    Task { await select(source: s) }
                                }
                            }
                        }
                    }
                }

                if !episodes.isEmpty {
                    sectionTitle("Серии")
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(episodes) { ep in
                            episodeButton(ep)
                        }
                    }
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if let error {
                    ErrorView(message: error) { Task { await loadTypes() } }
                } else if types.isEmpty {
                    Text("Для этого релиза пока нет серий").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(release.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if types.isEmpty { await loadTypes() } }
        .fullScreenCover(item: $playing) { item in
            PlayerView(item: item, episodes: episodes) { ep in
                if let t = selectedType { history.record(release: release, episode: ep, type: t) }
            }
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline)
    }

    private func chip(title: String, subtitle: String?, selected: Bool, icon: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption2).opacity(0.7) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func episodeButton(_ ep: Episode) -> some View {
        let watched = history.isWatched(releaseId: release.id, position: ep.position)
        let isLast = history.last(for: release.id)?.episodePosition == ep.position
        return Button {
            playing = PlayerItem(episode: ep, releaseTitle: release.title)
        } label: {
            VStack(spacing: 2) {
                Text("\(ep.position)").font(.headline)
                Text(ep.isFiller ? "филлер" : "серия").font(.caption2).opacity(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(watched ? Theme.card.opacity(0.5) : Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isLast ? Theme.accent : .clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if watched {
                    Image(systemName: "eye.fill").font(.system(size: 9)).padding(5).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(watched ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(watched ? "Отметить непросмотренной" : "Отметить просмотренной") {
                history.toggleWatched(releaseId: release.id, position: ep.position)
            }
        }
    }

    // MARK: Loading

    private func loadTypes() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            types = try await api.voiceovers(releaseId: release.id)
            let last = history.last(for: release.id)
            let preferred = types.first { $0.id == last?.typeId } ?? types.first
            if let preferred { await select(type: preferred) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func select(type: VoiceoverType) async {
        selectedType = type
        sources = []
        episodes = []
        selectedSource = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let s = try await api.sources(releaseId: release.id, typeId: type.id)
            guard selectedType?.id == type.id else { return }
            sources = s
            let last = history.last(for: release.id)
            // Prefer the last used player, then Kodik (best iframe compatibility), then the first one.
            let preferred = s.first { $0.id == last?.sourceId }
                ?? s.first { $0.name.localizedCaseInsensitiveContains("kodik") }
                ?? s.first
            if let preferred { await select(source: preferred) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func select(source: EpisodeSource) async {
        guard let type = selectedType else { return }
        selectedSource = source
        episodes = []
        isLoading = true
        defer { isLoading = false }
        do {
            let e = try await api.episodes(releaseId: release.id, typeId: type.id, sourceId: source.id)
            guard selectedSource?.id == source.id else { return }
            episodes = e
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PlayerItem: Identifiable {
    let episode: Episode
    let releaseTitle: String
    var id: String { episode.url }
}
