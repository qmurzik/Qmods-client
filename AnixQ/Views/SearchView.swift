import SwiftUI

struct SearchView: View {
    @StateObject private var pager = PagedReleases()
    @State private var query = ""
    @State private var submitted = ""
    @State private var debounce: Task<Void, Never>?
    @AppStorage("search.recent") private var recentRaw = ""

    private var recent: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    private let genres = ["экшен", "романтика", "комедия", "фэнтези", "исекай", "драма", "повседневность",
                          "психологическое", "детектив", "спорт", "ужасы", "меха", "музыка", "школа"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if submitted.isEmpty {
                    idleContent
                } else {
                    ForEach(pager.items) { release in
                        NavigationLink(value: ReleaseRoute(id: release.id)) {
                            ReleaseRow(release: release)
                        }
                        .buttonStyle(PressableStyle())
                        .onAppear {
                            if release.id == pager.items.last?.id { Task { await pager.loadMore() } }
                        }
                    }
                    if pager.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if let error = pager.error {
                        ErrorView(message: error) { run(submitted, remember: false) }
                    } else if pager.items.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", text: "По запросу «\(submitted)» ничего не найдено")
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Поиск")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Аниме, фильмы, OVA")
        .onSubmit(of: .search) { run(query, remember: true) }
        .onChange(of: query) { newValue in
            debounce?.cancel()
            let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { submitted = ""; return }
            guard q.count >= 2 else { return }
            debounce = Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if !Task.isCancelled { run(q, remember: false) }
            }
        }
        .releaseDestinations()
    }

    @ViewBuilder
    private var idleContent: some View {
        if !recent.isEmpty {
            HStack {
                Text("Недавние").font(.headline)
                Spacer()
                Button("Очистить") { recentRaw = "" }.font(.subheadline)
            }
            ForEach(recent, id: \.self) { q in
                Button {
                    query = q
                    run(q, remember: true)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.secondaryText)
                        Text(q).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 4)
        }
        Text("Жанры").font(.headline).padding(.top, 6)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(genres.enumerated()), id: \.element) { index, g in
                NavigationLink(value: GenreRoute(name: g)) {
                    GenreTile(name: g, index: index)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func run(_ raw: String, remember: Bool) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if remember {
            var list = recent.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
            list.insert(q, at: 0)
            recentRaw = list.prefix(8).joined(separator: "\n")
        }
        guard q != submitted || pager.items.isEmpty else { return }
        submitted = q
        Task {
            await pager.reset { page in try await AnixartAPI.shared.search(q, page: page) }
        }
    }
}

struct GenreTile: View {
    let name: String
    let index: Int

    private static let palettes: [[Color]] = [
        [Color(red: 1.0, green: 0.33, blue: 0.40), Color(red: 0.75, green: 0.15, blue: 0.45)],
        [Color(red: 0.36, green: 0.42, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 0.95)],
        [Color(red: 0.10, green: 0.75, blue: 0.65), Color(red: 0.10, green: 0.45, blue: 0.75)],
        [Color(red: 1.0, green: 0.60, blue: 0.20), Color(red: 0.95, green: 0.30, blue: 0.30)],
        [Color(red: 0.85, green: 0.30, blue: 0.90), Color(red: 0.40, green: 0.20, blue: 0.80)],
        [Color(red: 0.25, green: 0.70, blue: 0.95), Color(red: 0.20, green: 0.35, blue: 0.80)]
    ]

    var body: some View {
        let colors = Self.palettes[index % Self.palettes.count]
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 90)
                .offset(x: 110, y: -30)
            Text(name.capitalized)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
