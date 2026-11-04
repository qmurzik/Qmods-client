import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    @Published var banners: [InterestingItem] = []
    @Published var latest: [Release] = []
    @Published var top: [Release] = []
    @Published var popular: [Release] = []
    @Published var discussing: [Release] = []
    @Published var error: String?
    @Published var loaded = false

    private let api = AnixartAPI.shared

    func load() async {
        error = nil
        async let b = try? api.interesting()
        async let l = try? api.filter(CatalogFilter(sort: .updated), page: 0)
        async let t = try? api.filter(CatalogFilter(sort: .rating), page: 0)
        async let p = try? api.filter(CatalogFilter(sort: .popular), page: 0)
        async let d = try? api.discussing()
        let (banners, latest, top, popular, discussing) = await (b, l, t, p, d)
        self.banners = (banners ?? []).filter { $0.releaseId != nil }
        self.latest = latest?.content ?? []
        self.top = top?.content ?? []
        self.popular = popular?.content ?? []
        self.discussing = discussing ?? []
        if self.latest.isEmpty && self.banners.isEmpty {
            error = "Не удалось загрузить данные Anixart. Проверьте подключение."
        }
        loaded = true
    }
}

struct HomeView: View {
    @StateObject private var model = HomeModel()
    @EnvironmentObject private var history: HistoryStore
    @State private var randomId: Int?
    @State private var showRandom = false
    @State private var loadingRandom = false

    private let featuredGenres = ["экшен", "романтика", "комедия", "фэнтези", "исекай", "повседневность",
                                  "драма", "психологическое", "спорт", "ужасы", "меха", "школа"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !model.banners.isEmpty {
                    HeroCarousel(items: model.banners)
                } else {
                    Color.clear.frame(height: 100)
                }

                if !model.loaded {
                    ShelfPlaceholder()
                    ShelfPlaceholder()
                }

                if !history.entries.isEmpty {
                    ContinueWatchingShelf(entries: Array(history.entries.prefix(15)))
                }

                ReleaseShelf(title: "Новые серии", releases: model.latest,
                             more: SortRoute(sort: .updated, title: "Новые серии"))

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Жанры")
                    GenreChips(genres: featuredGenres)
                }

                ReleaseShelf(title: "Сейчас обсуждают", releases: model.discussing)
                ReleaseShelf(title: "Популярное", releases: model.popular,
                             more: SortRoute(sort: .popular, title: "Популярное"))
                ReleaseShelf(title: "Лучшие по рейтингу", releases: model.top,
                             more: SortRoute(sort: .rating, title: "Лучшие по рейтингу"))

                if let error = model.error {
                    ErrorView(message: error) { Task { await model.load() } }
                }
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showRandom) {
            if let randomId { ReleaseDetailView(releaseId: randomId) }
        }
        .releaseDestinations()
        .refreshable { await model.load() }
        .task { if !model.loaded { await model.load() } }
    }

    private var topBar: some View {
        HStack {
            Text("Anix")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.white)
            + Text("Q")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(Theme.accent)
            Spacer()
            Button {
                Task { await openRandom() }
            } label: {
                Group {
                    if loadingRandom { ProgressView().tint(.white) }
                    else { Image(systemName: "dice.fill").font(.system(size: 16, weight: .semibold)) }
                }
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
            }
            .accessibilityLabel("Случайное аниме")
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private func openRandom() async {
        loadingRandom = true
        defer { loadingRandom = false }
        if let r = try? await AnixartAPI.shared.randomRelease() {
            randomId = r.id
            showRandom = true
        }
    }
}

// MARK: - Hero

struct HeroCarousel: View {
    let items: [InterestingItem]
    @State private var selection = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HeroSlide(item: item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 470)

            HStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == selection ? Theme.accent : Color.white.opacity(0.25))
                        .frame(width: i == selection ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.3), value: selection)
        }
        .onReceive(timer) { _ in
            guard items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.5)) { selection = (selection + 1) % items.count }
        }
    }
}

struct HeroSlide: View {
    let item: InterestingItem

    var body: some View {
        NavigationLink(value: ReleaseRoute(id: item.releaseId ?? 0)) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: item.imageURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: Theme.background.opacity(0.7), location: 0.7),
                    .init(color: Theme.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    Pill(text: "Рекомендуем", icon: "sparkles", filled: true)
                    Text(item.title)
                        .font(.system(size: 28, weight: .heavy))
                        .lineLimit(3)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 8)
                    if let d = item.description, !d.isEmpty {
                        Text(d)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Смотреть")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Continue watching

struct ContinueWatchingShelf: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Продолжить просмотр")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: ReleaseRoute(id: entry.releaseId)) {
                            ContinueCard(entry: entry)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ContinueCard: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: entry.image.flatMap(URL.init(string:)))
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.episodeName).font(.system(size: 13, weight: .bold))
                        Text(entry.typeName).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    }
                    .lineLimit(1)
                }
                .padding(10)
            }
            .frame(width: 230, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))

            Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(width: 230, alignment: .leading)
        }
    }
}
