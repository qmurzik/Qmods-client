import SwiftUI
import AVKit
import AVFoundation

/// Drives AVPlayer for streams the app can resolve to plain HLS (AniLibria).
@MainActor
final class NativePlaybackController: NSObject, ObservableObject {
    let player = AVPlayer()

    @Published private(set) var qualities: [StreamQuality] = []
    @Published private(set) var selectedQuality: StreamQuality?
    @Published private(set) var skipRange: ClosedRange<Double>?
    @Published private(set) var inSkipRange = false
    @Published private(set) var isResolving = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var error: String?
    /// Incremented whenever the current episode plays to the end (used for auto-next).
    @Published private(set) var finishedCount = 0

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var loadedURL: String?
    /// AnimeLib serves the same file from several mirrors; on failure the next one is tried.
    private var animeLibHrefs: [(label: String, href: String)] = []
    private var animeLibServers: [String] = []
    private var serverIndex = 0
    private var loadStarted = Date()
    private var loggedFirstFrame = false
    var isScrubbing = false

    override init() {
        super.init()
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.tick(seconds) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in self?.updateStatus(status) }
        }
    }

    private static var preferredHeight: Int {
        get { UserDefaults.standard.object(forKey: "player.quality") as? Int ?? 720 }
        set { UserDefaults.standard.set(newValue, forKey: "player.quality") }
    }

    var isLoading: Bool { isResolving || (isBuffering && currentTime < 0.5) }

    func load(_ episode: Episode) async {
        guard loadedURL != episode.url, let pageURL = episode.playerURL else { return }
        loadedURL = episode.url
        loadStarted = Date()
        loggedFirstFrame = false
        DebugLog.log("native: resolve start \(pageURL.absoluteString)")
        player.pause()
        player.replaceCurrentItem(with: nil)
        qualities = []
        selectedQuality = nil
        skipRange = nil
        inSkipRange = false
        currentTime = 0
        duration = 0
        error = nil
        isResolving = true
        do {
            let stream: LibriaStream
            if let ref = episode.animeLibRef {
                stream = try await resolveAnimeLib(episodeId: ref.episodeId, teamId: ref.teamId)
            } else {
                animeLibHrefs = []
                stream = try await LibriaResolver.resolve(pageURL)
            }
            guard loadedURL == episode.url else { return }
            DebugLog.log(String(format: "native: resolved in %.2fs, qualities %@", Date().timeIntervalSince(loadStarted),
                                stream.qualities.map(\.label).joined(separator: ",")))
            qualities = stream.qualities
            skipRange = stream.skipOpening
            let preferred = stream.qualities.first { $0.height <= Self.preferredHeight } ?? stream.qualities.last
            if let preferred { play(preferred, at: nil) }
        } catch {
            guard loadedURL == episode.url else { return }
            DebugLog.log("native: resolve failed \(error)")
            self.error = error.localizedDescription
        }
        isResolving = false
    }

    private func resolveAnimeLib(episodeId: Int, teamId: Int) async throws -> LibriaStream {
        let players = try await AnimeLibAPI.players(episodeId: episodeId)
        guard let player = players.first(where: { $0.team.id == teamId && $0.isNative }) else {
            throw AnimeLibAPI.LibError.noVideo
        }
        animeLibHrefs = player.qualities
        let servers = await AnimeLibAPI.videoServers()
        // Probe a small range of the file on every mirror and use the fastest first.
        let probeHref = player.qualities.first { $0.label == "720p" }?.href ?? player.qualities[0].href
        animeLibServers = await AnimeLibAPI.rankServers(servers, href: probeHref)
        serverIndex = 0
        return LibriaStream(qualities: animeLibQualities(), skipOpening: nil)
    }

    private func animeLibQualities() -> [StreamQuality] {
        guard serverIndex < animeLibServers.count else { return [] }
        let server = animeLibServers[serverIndex]
        return animeLibHrefs.compactMap { q in
            AnimeLibAPI.videoURL(server: server, href: q.href).map { StreamQuality(label: q.label, url: $0) }
        }
        .sorted { $0.height > $1.height }
    }

    /// Switches to the next AnimeLib mirror, keeping quality and position.
    private func tryNextServer() -> Bool {
        guard !animeLibHrefs.isEmpty, serverIndex + 1 < animeLibServers.count else { return false }
        serverIndex += 1
        let label = selectedQuality?.label
        qualities = animeLibQualities()
        DebugLog.log("native: switching to server \(animeLibServers[serverIndex])")
        guard let q = qualities.first(where: { $0.label == label }) ?? qualities.first else { return false }
        error = nil
        play(q, at: currentTime > 1 ? currentTime : nil)
        return true
    }

    // MARK: Transport

    func togglePlay() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func seek(by delta: Double) {
        seek(to: max(0, min(duration > 0 ? duration - 1 : .greatestFiniteMagnitude, currentTime + delta)))
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func select(_ quality: StreamQuality) {
        guard quality != selectedQuality else { return }
        Self.preferredHeight = quality.height
        play(quality, at: currentTime > 1 ? currentTime : nil)
    }

    func skipOpening() {
        guard let range = skipRange else { return }
        seek(to: range.upperBound)
        inSkipRange = false
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    func reload() {
        if let q = selectedQuality {
            play(q, at: currentTime > 1 ? currentTime : nil)
        }
    }

    private func play(_ quality: StreamQuality, at time: Double?) {
        selectedQuality = quality
        DebugLog.log("native: play \(quality.label)")
        let asset = AVURLAsset(url: quality.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["Referer": animeLibHrefs.isEmpty ? "https://anixart.tv/" : "https://anilib.me/"]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 0
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finishedCount += 1 }
        }
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let dur = item.duration.seconds
            let err = item.error?.localizedDescription
            Task { @MainActor in self?.itemStatusChanged(status, duration: dur, error: err) }
        }
        player.replaceCurrentItem(with: item)
        if let time {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, duration: Double, error: String?) {
        switch status {
        case .readyToPlay:
            if duration.isFinite { self.duration = duration }
            DebugLog.log(String(format: "native: item ready after %.2fs", Date().timeIntervalSince(loadStarted)))
        case .failed:
            DebugLog.log("native: item failed \(error ?? "?")")
            if tryNextServer() { return }
            self.error = error ?? "Не удалось воспроизвести видео"
        default: break
        }
    }

    private func updateStatus(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status == .playing
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if status == .playing && !loggedFirstFrame {
            loggedFirstFrame = true
            DebugLog.log(String(format: "native: PLAYING after %.2fs", Date().timeIntervalSince(loadStarted)))
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if !isScrubbing { currentTime = seconds }
        if duration <= 0, let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        let inside = skipRange.map { $0.contains(seconds) && seconds < $0.upperBound - 2 } ?? false
        if inside != inSkipRange { inSkipRange = inside }
    }
}

// MARK: - Video surface

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Plain AVPlayerLayer surface (no AVKit view controller, so no AVKit fullscreen presentation that
/// SwiftUI would tear down). Also owns the Picture-in-Picture controller.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    @Binding var pip: AVPictureInPictureController?

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(playerLayer: v.playerLayer)
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            DispatchQueue.main.async { pip = controller }
        }
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

// MARK: - Controls

struct NativePlayerView: View {
    @ObservedObject var controller: NativePlaybackController
    let isFullscreen: Bool
    let toggleFullscreen: () -> Void

    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var pip: AVPictureInPictureController?
    @State private var scrubValue: Double = 0
    @State private var scrubbing = false

    var body: some View {
        ZStack {
            PlayerSurface(player: controller.player, pip: $pip)

            // Tap zones: single tap toggles controls, double tap left/right seeks 10s.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { controller.seek(by: -10); flash() }
                    .onTapGesture { toggleControls() }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { controller.seek(by: 10); flash() }
                    .onTapGesture { toggleControls() }
            }

            if showControls || !controller.isPlaying {
                controls.transition(.opacity)
            }

            if controller.isLoading || (controller.isBuffering && controller.isPlaying == false && controller.currentTime > 0) {
                ProgressView().tint(.white).scaleEffect(1.4).allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .onAppear { scheduleHide() }
        .onChange(of: controller.isPlaying) { playing in if playing { scheduleHide() } }
    }

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            HStack(spacing: 44) {
                circleButton("gobackward.10", size: 22) { controller.seek(by: -10) }
                circleButton(controller.isPlaying ? "pause.fill" : "play.fill", size: 30, big: true) {
                    controller.togglePlay()
                }
                .opacity(controller.isLoading ? 0 : 1)
                circleButton("goforward.10", size: 22) { controller.seek(by: 10) }
            }

            VStack {
                HStack {
                    Spacer()
                    if let pip {
                        iconButton("pip.enter") { pip.startPictureInPicture() }
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Text(format(scrubbing ? scrubValue : controller.currentTime))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Slider(value: Binding(get: { scrubbing ? scrubValue : controller.currentTime },
                                          set: { scrubValue = $0 }),
                           in: 0...max(controller.duration, 1)) { editing in
                        scrubbing = editing
                        controller.isScrubbing = editing
                        if editing {
                            scrubValue = controller.currentTime
                            hideTask?.cancel()
                        } else {
                            controller.seek(to: scrubValue)
                            scheduleHide()
                        }
                    }
                    .tint(Theme.accent)
                    Text(format(controller.duration))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    iconButton(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        toggleFullscreen()
                    }
                }
            }
            .padding(.horizontal, isFullscreen ? 24 : 12)
            .padding(.vertical, 8)
        }
        .foregroundStyle(.white)
    }

    private func circleButton(_ icon: String, size: CGFloat, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .frame(width: big ? 68 : 50, height: big ? 68 : 50)
                .background(.black.opacity(0.35), in: Circle())
        }
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
        }
    }

    private func toggleControls() {
        showControls.toggle()
        if showControls { scheduleHide() }
    }

    private func flash() {
        showControls = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled && controller.isPlaying && !scrubbing { showControls = false }
        }
    }

    private func format(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
