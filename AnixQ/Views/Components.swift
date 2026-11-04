import SwiftUI

// MARK: - Routes

struct ReleaseRoute: Hashable { let id: Int }
struct GenreRoute: Hashable { let name: String }
struct SortRoute: Hashable { let sort: CatalogSort; let title: String }

extension View {
    /// Registers every app-wide push destination. Call once at the root of each tab.
    func releaseDestinations() -> some View {
        self
            .navigationDestination(for: ReleaseRoute.self) { ReleaseDetailView(releaseId: $0.id) }
            .navigationDestination(for: GenreRoute.self) { route in
                FilteredListView(title: route.name.capitalized,
                                 filter: CatalogFilter(sort: .popular, genres: [route.name]))
            }
            .navigationDestination(for: SortRoute.self) { route in
                FilteredListView(title: route.title, filter: CatalogFilter(sort: route.sort))
            }
    }

    func cardStyle(radius: CGFloat = 16) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.stroke))
    }
}

// MARK: - Posters & cards

struct Poster: View {
    let url: URL?
    var ratio: CGFloat = 2.0 / 3.0
    var radius: CGFloat = 14

    var body: some View {
        Theme.card
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { RemoteImage(url: url) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.stroke))
    }
}

struct GradeBadge: View {
    let grade: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
            Text(String(format: "%.1f", grade)).font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.gradeColor(grade).opacity(0.92), in: Capsule())
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(filled ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08)),
                    in: Capsule())
        .foregroundStyle(.white)
    }
}

struct ReleaseCard: View {
    let release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Poster(url: release.imageURL)
                .overlay(alignment: .topLeading) {
                    if let g = release.grade, g > 0 { GradeBadge(grade: g).padding(7) }
                }
                .overlay(alignment: .bottomLeading) {
                    if release.status?.id == 2 {
                        Text("ВЫХОДИТ")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                            .padding(7)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(release.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.white)
                Text(release.cardSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

struct ReleaseRow: View {
    let release: Release
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Poster(url: release.imageURL, radius: 10)
                .frame(width: 70)
            VStack(alignment: .leading, spacing: 5) {
                Text(release.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                if let original = release.titleOriginal {
                    Text(original).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let g = release.grade, g > 0 { GradeBadge(grade: g) }
                    Text(release.cardSubtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Text(release.episodesText).font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.caption.bold()).foregroundStyle(Theme.accent)
            }
        }
        .padding(10)
        .cardStyle()
        .contentShape(Rectangle())
    }
}

struct ReleaseGrid: View {
    let releases: [Release]
    var onAppearLast: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(releases) { release in
                NavigationLink(value: ReleaseRoute(id: release.id)) {
                    ReleaseCard(release: release)
                }
                .buttonStyle(PressableStyle())
                .onAppear {
                    if release.id == releases.last?.id { onAppearLast?() }
                }
            }
        }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            trailing()
        }
        .padding(.horizontal)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

struct ReleaseShelf: View {
    let title: String
    let releases: [Release]
    var more: SortRoute? = nil
    var cardWidth: CGFloat = 122

    var body: some View {
        if !releases.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title) {
                    if let more {
                        NavigationLink(value: more) {
                            HStack(spacing: 2) {
                                Text("Все")
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(releases) { release in
                            NavigationLink(value: ReleaseRoute(id: release.id)) {
                                ReleaseCard(release: release).frame(width: cardWidth)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct ShelfPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(Theme.card).frame(width: 160, height: 20).padding(.horizontal)
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.card)
                            .frame(width: 122, height: 183)
                            .overlay(ShimmerView().clipShape(RoundedRectangle(cornerRadius: 14)))
                        RoundedRectangle(cornerRadius: 4).fill(Theme.card).frame(width: 100, height: 12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct GenreChips: View {
    let genres: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { g in
                    NavigationLink(value: GenreRoute(name: g)) {
                        Text(g.capitalized)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.stroke))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentGradient)
            Text(message).multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            Button("Повторить", action: retry)
                .buttonStyle(GradientButtonStyle())
                .frame(width: 180)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct EmptyStateView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.white.opacity(0.25))
            Text(text).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

extension Release {
    var cardSubtitle: String {
        [year, category?.name].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Paging

/// Generic paginated loader for `Page<Release>` endpoints.
@MainActor
final class PagedReleases: ObservableObject {
    @Published var items: [Release] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var reachedEnd = false

    private var page = 0
    private var generation = 0
    private var fetcher: ((Int) async throws -> Page<Release>)?

    func reset(_ fetcher: @escaping (Int) async throws -> Page<Release>) async {
        generation += 1
        self.fetcher = fetcher
        items = []
        page = 0
        reachedEnd = false
        error = nil
        isLoading = false
        await loadMore()
    }

    func loadMore() async {
        guard let fetcher, !isLoading, !reachedEnd else { return }
        let gen = generation
        isLoading = true
        defer { if gen == generation { isLoading = false } }
        do {
            let result = try await fetcher(page)
            guard gen == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: result.content.filter { !known.contains($0.id) })
            page += 1
            if result.content.isEmpty || (result.totalPageCount > 0 && page >= result.totalPageCount) {
                reachedEnd = true
            }
        } catch {
            guard gen == generation else { return }
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }
}

struct FilteredListView: View {
    let title: String
    let filter: CatalogFilter
    @StateObject private var pager = PagedReleases()

    var body: some View {
        ScrollView {
            VStack {
                ReleaseGrid(releases: pager.items) { Task { await pager.loadMore() } }
                if pager.isLoading {
                    ProgressView().padding()
                } else if let error = pager.error {
                    ErrorView(message: error) { Task { await reload() } }
                } else if pager.items.isEmpty {
                    EmptyStateView(icon: "tray", text: "Ничего не найдено")
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .refreshable { await reload() }
        .task { if pager.items.isEmpty { await reload() } }
    }

    private func reload() async {
        let f = filter
        await pager.reset { try await AnixartAPI.shared.filter(f, page: $0) }
    }
}
