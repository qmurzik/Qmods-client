import SwiftUI
import PhotosUI
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Search by screenshot (trace.moe)

struct TraceResult: Identifiable, Hashable {
    let id = UUID()
    let anilistId: Int
    let names: [String]
    let episode: String?
    let from: Double
    let similarity: Double
    let image: URL?
}

enum TraceMoe {
    static func search(_ data: Data) async throws -> [TraceResult] {
        var req = URLRequest(url: URL(string: "https://api.trace.moe/search?cutBorders&anilistInfo")!)
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 40
        let (body, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 402 || status == 429 { throw LibError.server("Лимит поиска trace.moe исчерпан, попробуйте позже") }
            throw LibError.badStatus(status)
        }
        let json = try JSONSerialization.jsonObject(with: body) as? JSON ?? [:]
        var seen = Set<String>()
        return json.arr("result").compactMap { r -> TraceResult? in
            guard let a = r.obj("anilist"), let id = a.int("id") else { return nil }
            let t = a.obj("title") ?? [:]
            let ep = r.str("episode")
            guard seen.insert("\(id)-\(ep ?? "")").inserted else { return nil }
            let names = [t.str("romaji"), t.str("english"), t.str("native")].compactMap { $0 }
                + (a["synonyms"] as? [String] ?? [])
            return TraceResult(anilistId: id, names: names, episode: ep, from: r.double("from") ?? 0,
                               similarity: r.double("similarity") ?? 0, image: r.str("image").flatMap(URL.init(string:)))
        }
    }

    /// AnimeLib stores AniList ids, so a name search plus id check finds the exact title.
    static func resolve(_ r: TraceResult) async -> Title? {
        for name in r.names.prefix(4) {
            if let hit = try? await LibAPI.search(name).first(where: { $0.anilistId == r.anilistId }) { return hit }
        }
        return nil
    }
}

struct TraceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var results: [TraceResult] = []
    @State private var searching = false
    @State private var error: String?
    @State private var resolving: UUID?
    @State private var opened: Title?
    @State private var showOpened = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label(image == nil ? "Выбрать скриншот" : "Другой скриншот", systemImage: "photo.on.rectangle")
                    }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } footer: {
                    Text("Кадр из аниме — найдём тайтл, серию и момент. Поиск через trace.moe.")
                }
                if searching { HStack { Spacer(); ProgressView("Ищем…"); Spacer() } }
                if let error { Text(error).foregroundStyle(.red) }
                if !results.isEmpty {
                    Section("Результаты") {
                        ForEach(results) { r in
                            Button { Task { await open(r) } } label: { row(r) }
                        }
                    }
                }
            }
            .navigationTitle("Поиск по кадру")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .navigationDestination(isPresented: $showOpened) {
                if let opened { TitleView(title: opened) }
            }
            .appDestinations()
            .onChange(of: pick) { item in Task { await load(item) } }
        }
    }

    private func row(_ r: TraceResult) -> some View {
        HStack(spacing: 12) {
            Theme.card.frame(width: 96, height: 54).overlay { RemoteImage(url: r.image) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(r.names.first ?? "?").font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                Text([r.episode.map { "Серия \($0)" }, time(r.from)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if resolving == r.id { ProgressView() } else {
                Text("\(Int(r.similarity * 100))%").font(.caption.weight(.bold))
                    .foregroundStyle(r.similarity > 0.9 ? .green : .orange)
            }
        }
    }

    private func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        image = img
        results = []
        error = nil
        searching = true
        defer { searching = false }
        // trace.moe limits upload size; a ~1000px JPEG is plenty.
        let scale = min(1, 1000 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = small.jpegData(compressionQuality: 0.8) else { return }
        do {
            results = try await TraceMoe.search(jpeg)
            if results.isEmpty { error = "Ничего не нашлось" }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func open(_ r: TraceResult) async {
        resolving = r.id
        defer { resolving = nil }
        if let t = await TraceMoe.resolve(r) {
            opened = t
            showOpened = true
        } else {
            error = "Этого тайтла нет на AnimeLib"
        }
    }
}

// MARK: - "Что посмотреть?"

struct RandomPickView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @State private var genres: [Genre] = []
    @State private var selectedGenres: Set<Int> = []
    @State private var type: CatalogType?
    @State private var onlyFinished = true
    @State private var minScore: Double = 7
    @State private var pick: Title?
    @State private var summary: String?
    @State private var loading = false
    @State private var pool: [Title] = []

    var body: some View {
        NavigationStack {
            Form {
                if let pick {
                    Section {
                        NavigationLink(value: pick) {
                            HStack(alignment: .top, spacing: 14) {
                                PosterImage(url: pick.coverURL, radius: 10).frame(width: 100)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(pick.title).font(.headline)
                                    Text(pick.metaLine).font(.caption).foregroundStyle(.secondary)
                                    if let s = pick.score { ScoreBadge(score: s) }
                                    if let summary {
                                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(6)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        Task { await roll() }
                    } label: {
                        HStack {
                            Spacer()
                            if loading { ProgressView() } else { Label(pick == nil ? "Подобрать" : "Другой вариант", systemImage: "dice.fill").bold() }
                            Spacer()
                        }
                    }
                }
                Section("Фильтры") {
                    Picker("Тип", selection: $type) {
                        Text("Любой").tag(CatalogType?.none)
                        ForEach(CatalogType.allCases) { Text($0.title).tag(CatalogType?.some($0)) }
                    }
                    Toggle("Только завершённые", isOn: $onlyFinished)
                    VStack(alignment: .leading) {
                        Text("Рейтинг от \(String(format: "%.1f", minScore))")
                        Slider(value: $minScore, in: 0...9.5, step: 0.5)
                    }
                }
                Section("Жанры") {
                    if genres.isEmpty { ProgressView() }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(genres) { g in
                            let on = selectedGenres.contains(g.id)
                            Text(g.name).font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.thinMaterial),
                                            in: Capsule())
                                .onTapGesture {
                                    if on { selectedGenres.remove(g.id) } else { selectedGenres.insert(g.id) }
                                    pool = []
                                }
                        }
                    }
                }
            }
            .navigationTitle("Что посмотреть?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .appDestinations()
            .task { if genres.isEmpty { genres = await LibAPI.genres() } }
            .onChange(of: type) { _ in pool = [] }
            .onChange(of: onlyFinished) { _ in pool = [] }
            .onChange(of: minScore) { _ in pool = [] }
        }
    }

    private func roll() async {
        loading = true
        defer { loading = false }
        if pool.isEmpty {
            var q = CatalogQuery(sort: .rating)
            q.genres = selectedGenres
            if let type { q.types = [type] }
            if onlyFinished { q.statuses = [.finished] }
            let known = Set(library.history.map(\.title.id)).union(library.bookmarks.values.map(\.title.id))
            for page in [1, Int.random(in: 2...4)] {
                let items = (try? await LibAPI.catalog(q, page: page).items) ?? []
                pool += items.filter { ($0.score ?? 0) >= minScore && !known.contains($0.id) }
            }
        }
        guard !pool.isEmpty else { pick = nil; summary = "Ничего не подошло — ослабьте фильтры"; return }
        let choice = pool.remove(at: Int.random(in: 0..<pool.count))
        pick = choice
        summary = nil
        summary = (try? await LibAPI.detail(choice.slugURL))?.summary
    }
}

// MARK: - Spotlight

/// Puts bookmarked and recently watched titles into system search.
enum SpotlightIndexer {
    static let domain = "ru.qmods.anixq.titles"

    static func update(_ titles: [Title]) {
        let items = titles.prefix(300).map { t -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = t.title
            attrs.alternateNames = [t.name, t.engName].compactMap { $0 }
            attrs.contentDescription = t.metaLine
            attrs.thumbnailURL = t.thumbURL
            return CSSearchableItem(uniqueIdentifier: "title:" + t.slugURL, domainIdentifier: domain, attributeSet: attrs)
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            CSSearchableIndex.default().indexSearchableItems(Array(items)) { error in
                if let error { DebugLog.log("spotlight: \(error.localizedDescription)") }
            }
        }
    }
}
