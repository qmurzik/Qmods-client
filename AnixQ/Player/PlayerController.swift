import SwiftUI
import AVFoundation
import MediaPlayer

/// Playback state for one title: current episode, team (dub), stream, progress and sync.
@MainActor
final class PlayerController: ObservableObject {
    let player = AVPlayer()
    let title: Title
    let episodes: [LibEpisode]
    let teams: [TeamOption]

    @Published private(set) var index: Int
    @Published private(set) var team: TeamOption
    @Published private(set) var qualities: [StreamQuality] = []
    @Published private(set) var quality: StreamQuality?
    @Published private(set) var kodikURL: URL?
    @Published private(set) var isResolving = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var nextCountdown: Int?
    @Published var rate: Float = 1 { didSet { if isPlaying { player.rate = rate } } }
    @Published var isScrubbing = false
    @Published var fillScreen = false

    weak var library: LibraryStore?

    private var hrefs: [String: String] = [:]
    private var servers: [String] = []
    private var serverIndex = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var loadToken = UUID()
    private var startedAt = Date()
    private var lastSaved = Date.distantPast
    private var autoSkipped = false
    private var markedWatched = false
    private var countdownTask: Task<Void, Never>?

    var episode: LibEpisode { episodes[index] }
    var isNative: Bool { team.native }
    var hasNext: Bool { index + 1 < episodes.count }
    var hasPrevious: Bool { index > 0 }
    var isLoading: Bool { isResolving || (isBuffering && currentTime < 0.5) }
    var openingRange: ClosedRange<Double> { 0...(PlayerPrefs.openingLength + 30) }
    var canSkipOpening: Bool { isNative && currentTime > 3 && currentTime < 240 && !autoSkipped }
    var nearEnd: Bool { duration > 0 && duration - currentTime < 100 && hasNext }

    init(title: Title, episodes: [LibEpisode], teams: [TeamOption], index: Int, team: TeamOption) {
        self.title = title
        self.episodes = episodes
        self.teams = teams
        self.index = min(max(0, index), max(0, episodes.count - 1))
        self.team = team
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] t in
            let s = t.seconds
            Task { @MainActor in self?.tick(s) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let st = p.timeControlStatus
            Task { @MainActor in self?.statusChanged(st) }
        }
        setupRemoteCommands()
    }

    // MARK: Loading

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        Task { await load() }
    }

    func load() async {
        let token = UUID()
        loadToken = token
        saveProgress(force: true)
        player.pause()
        player.replaceCurrentItem(with: nil)
        countdownTask?.cancel()
        nextCountdown = nil
        qualities = []
        quality = nil
        kodikURL = nil
        error = nil
        currentTime = 0
        duration = 0
        autoSkipped = false
        markedWatched = false
        isResolving = true
        startedAt = Date()
        let ep = episode
        DebugLog.log("player: load ep \(ep.number) team \(team.team.name) native=\(team.native)")
        do {
            let players = try await LibAPI.players(episodeId: ep.id)
            guard token == loadToken else { return }
            if team.native, let p = players.first(where: { $0.team.id == team.id && $0.isNative }) {
                hrefs = p.hrefs
                let probe = p.hrefs["720p"] ?? p.hrefs.values.first ?? ""
                servers = await LibAPI.rankServers(await LibAPI.videoServers(), href: probe)
                guard token == loadToken else { return }
                serverIndex = 0
                rebuildQualities()
                let preferred = qualities.first { $0.height <= PlayerPrefs.preferredHeight } ?? qualities.last
                if let preferred { play(preferred, at: library?.resumePosition(episodeId: ep.id)) }
                DebugLog.log(String(format: "player: resolved in %.2fs", Date().timeIntervalSince(startedAt)))
                if hasNext { LibAPI.warmUp(episodeId: episodes[index + 1].id, teamId: team.id) }
            } else if let p = players.first(where: { $0.team.id == team.id && $0.isKodik }),
                      let src = p.kodikSrc, let url = LibAPI.kodikURL(src) {
                kodikURL = url
            } else {
                throw LibError.noVideo
            }
        } catch {
            guard token == loadToken else { return }
            self.error = error.localizedDescription
            DebugLog.log("player: load failed \(error)")
        }
        isResolving = false
        updateNowPlaying()
    }

    private func rebuildQualities() {
        guard serverIndex < servers.count else { qualities = []; return }
        let server = servers[serverIndex]
        qualities = hrefs.compactMap { label, href in
            LibAPI.videoURL(server: server, href: href).map { StreamQuality(label: label, url: $0) }
        }
        .sorted { $0.height > $1.height }
    }

    private func play(_ q: StreamQuality, at time: Double?) {
        quality = q
        let asset = AVURLAsset(url: q.url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Referer": LibAPI.site + "/"]])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 0
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                             queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didFinish() }
        }
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let st = item.status
            let d = item.duration.seconds
            let e = item.error?.localizedDescription
            Task { @MainActor in self?.itemStatus(st, duration: d, error: e) }
        }
        player.replaceCurrentItem(with: item)
        if let time, time > 1 {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = time
        }
        player.playImmediately(atRate: rate)
    }

    private func itemStatus(_ st: AVPlayerItem.Status, duration d: Double, error e: String?) {
        switch st {
        case .readyToPlay:
            if d.isFinite { duration = d }
            DebugLog.log(String(format: "player: ready after %.2fs", Date().timeIntervalSince(startedAt)))
        case .failed:
            DebugLog.log("player: item failed \(e ?? "?") on \(servers[safe: serverIndex] ?? "?")")
            if serverIndex + 1 < servers.count {
                serverIndex += 1
                let label = quality?.label
                rebuildQualities()
                if let q = qualities.first(where: { $0.label == label }) ?? qualities.first {
                    play(q, at: currentTime > 1 ? currentTime : nil)
                    return
                }
            }
            error = e ?? "Не удалось воспроизвести видео"
        default: break
        }
    }

    // MARK: Transport

    func togglePlay() {
        if player.timeControlStatus == .paused {
            if duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }
            player.playImmediately(atRate: rate)
        } else {
            player.pause()
        }
    }

    func seek(to s: Double) {
        let target = max(0, duration > 0 ? min(duration - 0.5, s) : s)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seek(by delta: Double) { seek(to: currentTime + delta) }

    func skipOpening() {
        autoSkipped = true
        seek(by: PlayerPrefs.openingLength)
    }

    func select(quality q: StreamQuality) {
        guard q != quality else { return }
        PlayerPrefs.preferredHeight = q.height
        play(q, at: currentTime)
    }

    func select(team t: TeamOption) {
        guard t != team else { return }
        let resume = currentTime
        team = t
        TitleModel.preferredTeamName = t.team.name
        Task {
            await load()
            if resume > 5, t.native { seek(to: resume) }
        }
    }

    func go(to i: Int) {
        guard episodes.indices.contains(i), i != index else { return }
        index = i
        Task { await load() }
    }

    func next() { go(to: index + 1) }
    func previous() { go(to: index - 1) }

    func cancelCountdown() {
        countdownTask?.cancel()
        nextCountdown = nil
    }

    func stop() {
        saveProgress(force: true)
        countdownTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Observers

    private func statusChanged(_ st: AVPlayer.TimeControlStatus) {
        isPlaying = st == .playing
        isBuffering = st == .waitingToPlayAtSpecifiedRate
        if st == .playing, Date().timeIntervalSince(startedAt) < 120, currentTime < 2 {
            DebugLog.log(String(format: "player: PLAYING after %.2fs", Date().timeIntervalSince(startedAt)))
        }
        updateNowPlaying()
    }

    private func tick(_ s: Double) {
        guard s.isFinite else { return }
        if !isScrubbing { currentTime = s }
        if duration <= 0, let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if PlayerPrefs.autoSkipOpening, !autoSkipped, isNative, s > 2, s < 15, duration > 300 {
            skipOpening()
        }
        if duration > 0, s / duration > 0.9, !markedWatched {
            markedWatched = true
            library?.markWatched(title: title, episode: episode, totalEpisodes: episodes.count)
        }
        saveProgress(force: false)
    }

    private func didFinish() {
        saveProgress(force: true)
        if !markedWatched {
            markedWatched = true
            library?.markWatched(title: title, episode: episode, totalEpisodes: episodes.count)
        }
        guard hasNext, PlayerPrefs.autoNext else { return }
        countdownTask?.cancel()
        countdownTask = Task {
            for n in stride(from: 5, through: 1, by: -1) {
                nextCountdown = n
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            nextCountdown = nil
            next()
        }
    }

    private func saveProgress(force: Bool) {
        guard let library, duration > 0, currentTime > 1 else { return }
        guard force || Date().timeIntervalSince(lastSaved) > 5 else { return }
        lastSaved = Date()
        library.updateProgress(title: title, episode: episode, team: team.team, position: currentTime, duration: duration)
    }

    // MARK: Lock screen / Control Center

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(by: 10) }; return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seek(by: -10) }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let pos = e.positionTime
            Task { @MainActor in self?.seek(to: pos) }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Серия \(episode.number)",
            MPMediaItemPropertyArtist: title.title,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let url = title.coverURL, let img = ImagePipeline.shared.cached(url) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let c = MPRemoteCommandCenter.shared()
        [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.skipForwardCommand, c.skipBackwardCommand,
         c.nextTrackCommand, c.changePlaybackPositionCommand].forEach { $0.removeTarget(nil) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
