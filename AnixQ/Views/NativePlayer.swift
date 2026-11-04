import SwiftUI
import AVKit
import AVFoundation

/// Drives AVPlayer for streams the app can resolve to plain HLS (AniLibria).
@MainActor
final class NativePlaybackController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var qualities: [StreamQuality] = []
    @Published private(set) var selectedQuality: StreamQuality?
    @Published private(set) var skipRange: ClosedRange<Double>?
    @Published private(set) var inSkipRange = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    /// Incremented whenever the current episode plays to the end (used for auto-next).
    @Published private(set) var finishedCount = 0

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadedURL: String?

    init() {
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.updateSkip(seconds) }
        }
    }

    private static var preferredHeight: Int {
        get { UserDefaults.standard.object(forKey: "player.quality") as? Int ?? 1080 }
        set { UserDefaults.standard.set(newValue, forKey: "player.quality") }
    }

    func load(_ episode: Episode) async {
        guard loadedURL != episode.url, let pageURL = episode.playerURL else { return }
        loadedURL = episode.url
        player.pause()
        player.replaceCurrentItem(with: nil)
        qualities = []
        selectedQuality = nil
        skipRange = nil
        inSkipRange = false
        error = nil
        isLoading = true
        do {
            let stream = try await LibriaResolver.resolve(pageURL)
            guard loadedURL == episode.url else { return }
            qualities = stream.qualities
            skipRange = stream.skipOpening
            let preferred = stream.qualities.first { $0.height <= Self.preferredHeight } ?? stream.qualities.last
            if let preferred { play(preferred, at: nil) }
        } catch {
            guard loadedURL == episode.url else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func select(_ quality: StreamQuality) {
        guard quality != selectedQuality else { return }
        Self.preferredHeight = quality.height
        let time = player.currentTime()
        play(quality, at: time.isValid ? time : nil)
    }

    func skipOpening() {
        guard let range = skipRange else { return }
        player.seek(to: CMTime(seconds: range.upperBound, preferredTimescale: 600))
        inSkipRange = false
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    func reload() {
        guard let q = selectedQuality else { return }
        let time = player.currentTime()
        play(q, at: time.isValid ? time : nil)
    }

    private func play(_ quality: StreamQuality, at time: CMTime?) {
        selectedQuality = quality
        let item = AVPlayerItem(url: quality.url)
        item.preferredForwardBufferDuration = 20
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finishedCount += 1 }
        }
        player.replaceCurrentItem(with: item)
        if let time { player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) }
        player.play()
    }

    private func updateSkip(_ seconds: Double) {
        let inside = skipRange.map { $0.contains(seconds) && seconds < $0.upperBound - 2 } ?? false
        if inside != inSkipRange { inSkipRange = inside }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}

/// System video player: native controls, fullscreen, PiP, AirPlay.
struct NativeVideoView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = false
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
