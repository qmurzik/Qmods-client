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

    var body: some View {
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
