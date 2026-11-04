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
        self.banners = banners ?? []
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !model.banners.isEmpty {
                    BannerCarousel(items: model.banners)
                }
                if !history.entries.isEmpty {
                    ContinueWatchingRow(entries: Array(history.entries.prefix(15)))
                }
                HorizontalReleases(title: "Последние обновления", releases: model.latest)
                HorizontalReleases(title: "Обсуждаемое", releases: model.discussing)
                HorizontalReleases(title: "Популярное", releases: model.popular)
                HorizontalReleases(title: "Топ по рейтингу", releases: model.top)
                if let error = model.error {
                    ErrorView(message: error) { Task { await model.load() } }
                } else if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.background)
        .navigationTitle("AnixQ")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        if let r = try? await AnixartAPI.shared.randomRelease() {
                            randomId = r.id
                            showRandom = true
                        }
                    }
                } label: {
                    Image(systemName: "shuffle")
                }
                .accessibilityLabel("Случайное аниме")
            }
        }
        .navigationDestination(isPresented: $showRandom) {
            if let randomId { ReleaseDetailView(releaseId: randomId) }
        }
        .releaseDestinations()
        .refreshable { await model.load() }
        .task { if !model.loaded { await model.load() } }
    }
}

struct BannerCarousel: View {
    let items: [InterestingItem]

    var body: some View {
        TabView {
            ForEach(items) { item in
                Group {
                    if let id = item.releaseId {
                        NavigationLink(value: ReleaseRoute(id: id)) { banner(item) }
                            .buttonStyle(.plain)
                    } else {
                        banner(item)
                    }
                }
                .padding(.horizontal)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 220)
    }

    private func banner(_ item: InterestingItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: item.imageURL, cornerRadius: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                if let d = item.description {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding()
        }
    }
}

struct ContinueWatchingRow: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Продолжить просмотр").font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: ReleaseRoute(id: entry.releaseId)) {
                            VStack(alignment: .leading, spacing: 4) {
                                PosterImage(url: entry.image.flatMap(URL.init(string:)))
                                    .frame(width: 200, height: 112)
                                Text(entry.title).font(.footnote.weight(.semibold)).lineLimit(1)
                                Text("\(entry.episodeName) · \(entry.typeName)")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 200)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
