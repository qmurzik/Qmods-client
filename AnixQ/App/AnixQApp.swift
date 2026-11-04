import SwiftUI
import UIKit

@main
struct AnixQApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var history = HistoryStore()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(history)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { AdBlocker.shared.warmUp() }
        }
    }
}

enum Theme {
    static let accent = Color(red: 1.0, green: 0.27, blue: 0.42)
    static let accent2 = Color(red: 0.55, green: 0.30, blue: 1.0)
    static let background = Color(red: 0.043, green: 0.043, blue: 0.063)
    static let card = Color(red: 0.090, green: 0.090, blue: 0.122)
    static let cardHighlight = Color(red: 0.135, green: 0.135, blue: 0.180)
    static let stroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.6)

    static let accentGradient = LinearGradient(colors: [accent, accent2],
                                               startPoint: .leading, endPoint: .trailing)

    static func gradeColor(_ grade: Double) -> Color {
        switch grade {
        case 4.5...: return Color(red: 0.22, green: 0.80, blue: 0.45)
        case 3.8..<4.5: return Color(red: 0.98, green: 0.72, blue: 0.20)
        default: return Color(red: 0.95, green: 0.35, blue: 0.35)
        }
    }

    static func configureAppearance() {
        let bg = UIColor(red: 0.043, green: 0.043, blue: 0.063, alpha: 1)

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        tab.backgroundColor = bg.withAlphaComponent(0.75)
        tab.shadowColor = UIColor.white.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        nav.backgroundColor = bg.withAlphaComponent(0.7)
        nav.shadowColor = .clear
        let bold = UIFont.systemFont(ofSize: 34, weight: .heavy)
        nav.largeTitleTextAttributes = [.font: bold, .foregroundColor: UIColor.white]
        nav.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                                   .foregroundColor: UIColor.white]
        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.largeTitleTextAttributes = nav.largeTitleTextAttributes
        transparent.titleTextAttributes = nav.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = transparent

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(accent)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }
}

struct RootView: View {
    // Launch arguments used by the CI screenshot job: `-screenshotTab 1`, `-screenshotRelease 20024`.
    @State private var tab = UserDefaults.standard.integer(forKey: "screenshotTab")
    private let screenshotRelease = UserDefaults.standard.integer(forKey: "screenshotRelease")

    private let autoplayRelease = UserDefaults.standard.integer(forKey: "autoplayRelease")

    var body: some View {
        if autoplayRelease > 0 {
            DebugAutoplayView(releaseId: autoplayRelease)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack {
                if screenshotRelease > 0 {
                    ReleaseDetailView(releaseId: screenshotRelease).releaseDestinations()
                } else {
                    HomeView()
                }
            }
            .tabItem { Label("Главная", systemImage: "play.house.fill") }
            .tag(0)
            NavigationStack { CatalogView() }
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            NavigationStack { SearchView() }
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(2)
            NavigationStack { ScheduleView() }
                .tabItem { Label("Расписание", systemImage: "calendar") }
                .tag(3)
            NavigationStack { ProfileView() }
                .tabItem { Label("Профиль", systemImage: "person.fill") }
                .tag(4)
        }
    }
}

/// CI player test: `-autoplayRelease 2804 -autoplayType 2 -autoplaySource Kodik -autoLandscapeAfter 40`.
/// Opens the player directly so the simulator run can measure start-up time and check fullscreen.
struct DebugAutoplayView: View {
    let releaseId: Int
    @StateObject private var episodes: EpisodesModel
    @State private var release: Release?
    @State private var ready = false

    init(releaseId: Int) {
        self.releaseId = releaseId
        _episodes = StateObject(wrappedValue: EpisodesModel(releaseId: releaseId))
    }

    var body: some View {
        Group {
            if ready, let release, let first = episodes.episodes.first {
                PlayerView(release: release, start: first, model: episodes)
            } else {
                ProgressView()
            }
        }
        .task {
            let defaults = UserDefaults.standard
            DebugLog.log("autoplay: start release \(releaseId)")
            release = try? await AnixartAPI.shared.release(releaseId)
            let typeId = defaults.integer(forKey: "autoplayType")
            await episodes.load(preferredTypeId: typeId > 0 ? typeId : nil, preferredSourceId: nil)
            if defaults.string(forKey: "autoplayProvider") == "animelib", let release {
                await episodes.switchProvider(.animelib, release: release)
            }
            if let name = defaults.string(forKey: "autoplaySource"),
               let source = episodes.sources.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                await episodes.select(source: source)
            }
            DebugLog.log("autoplay: type=\(episodes.selectedType?.name ?? "-") source=\(episodes.selectedSource?.name ?? "-") episodes=\(episodes.episodes.count)")
            ready = true
            let after = defaults.integer(forKey: "autoLandscapeAfter")
            if after > 0 {
                try? await Task.sleep(nanoseconds: UInt64(after) * 1_000_000_000)
                DebugLog.log("autoplay: rotate to landscape")
                OrientationController.set(.landscape)
            }
        }
    }
}
