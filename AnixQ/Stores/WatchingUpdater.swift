import Foundation
import Network
import SwiftUI

/// Checks titles the user is watching for new episodes on AnimeLib and, on Wi-Fi, pre-downloads
/// the next unwatched ones.
@MainActor
final class WatchingUpdater: ObservableObject {
    static let shared = WatchingUpdater()

    /// titleId -> number of episodes available after the last one watched.
    @Published private(set) var newEpisodes: [Int: Int] = [:]
    @Published private(set) var isChecking = false
    private(set) var titlesWithNew: [Title] = []
    private var lastCheck = Date.distantPast
    private var onWiFi = false
    private let monitor = NWPathMonitor()

    static var autoDownload: Bool {
        get { UserDefaults.standard.bool(forKey: "autodl.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "autodl.enabled") }
    }
    static var autoDownloadCount: Int {
        get { max(1, UserDefaults.standard.object(forKey: "autodl.count") as? Int ?? 2) }
        set { UserDefaults.standard.set(newValue, forKey: "autodl.count") }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "newEpisodes"),
           let saved = try? JSONDecoder().decode([Int: Int].self, from: data) {
            newEpisodes = saved
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive
            Task { @MainActor in self?.onWiFi = wifi }
        }
        monitor.start(queue: DispatchQueue(label: "net.monitor"))
    }

    func newCount(_ titleId: Int) -> Int { newEpisodes[titleId] ?? 0 }

    func refresh(library: LibraryStore, force: Bool = false) async {
        guard !isChecking, force || Date().timeIntervalSince(lastCheck) > 30 * 60 else { return }
        isChecking = true
        defer { isChecking = false }
        lastCheck = Date()

        var candidates: [Title] = library.watchingTitles
        for entry in library.history.prefix(15) where !candidates.contains(where: { $0.id == entry.title.id }) {
            let status = library.bookmark(for: entry.title.slugURL)
            if status == nil || status == .watching || status == .rewatching { candidates.append(entry.title) }
        }

        var result: [Int: Int] = [:]
        var withNew: [Title] = []
        for title in candidates.prefix(30) {
            guard let episodes = try? await LibAPI.episodes(slug: title.slugURL), !episodes.isEmpty else { continue }
            let lastWatched = lastWatchedNumber(title: title, library: library)
            guard lastWatched > 0 else { continue }
            let fresh = episodes.filter { $0.numberValue > lastWatched }
            if !fresh.isEmpty {
                result[title.id] = fresh.count
                withNew.append(title)
            }
            if Self.autoDownload, onWiFi { autoDownload(title: title, fresh: fresh, library: library) }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        newEpisodes = result
        titlesWithNew = withNew
        if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: "newEpisodes") }
        DebugLog.log("updater: \(candidates.count) titles checked, \(withNew.count) with new episodes, wifi=\(onWiFi)")
    }

    private func lastWatchedNumber(title: Title, library: LibraryStore) -> Double {
        let watched = (library.watched[title.id] ?? []).compactMap(Double.init).max() ?? 0
        let inHistory = library.lastEntry(titleId: title.id).flatMap { Double($0.episodeNumber) } ?? 0
        return max(watched, inHistory)
    }

    /// Downloads the next unwatched episodes with the team the user watched last (ad-free players only).
    private func autoDownload(title: Title, fresh: [LibEpisode], library: LibraryStore) {
        guard let last = library.lastEntry(titleId: title.id) else { return }
        let team = LibTeam(id: last.teamId, name: last.teamName, isSubtitles: false)
        for ep in fresh.prefix(Self.autoDownloadCount)
        where DownloadManager.shared.item(episodeId: ep.id, teamId: team.id) == nil {
            DownloadManager.shared.download(title: title, episode: ep, team: team)
            DebugLog.log("updater: auto-download \(title.title) ep \(ep.number)")
        }
    }

    /// Called after an episode is watched so the badge updates immediately.
    func episodeWatched(titleId: Int) {
        guard let n = newEpisodes[titleId] else { return }
        newEpisodes[titleId] = n > 1 ? n - 1 : nil
        titlesWithNew.removeAll { newEpisodes[$0.id] == nil }
    }
}
