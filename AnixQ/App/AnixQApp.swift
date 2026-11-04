import SwiftUI

@main
struct AnixQApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var history = HistoryStore()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
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
    static let accent = Color(red: 0.91, green: 0.18, blue: 0.40)
    static let card = Color(white: 0.12)
    static let background = Color(white: 0.06)
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "house.fill") }
            NavigationStack { CatalogView() }
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2.fill") }
            NavigationStack { SearchView() }
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            NavigationStack { ScheduleView() }
                .tabItem { Label("Расписание", systemImage: "calendar") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
    }
}
