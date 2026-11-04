import SwiftUI

/// Navigation value so any screen can push a release by id.
struct ReleaseRoute: Hashable {
    let id: Int
}

extension View {
    func releaseDestinations() -> some View {
        navigationDestination(for: ReleaseRoute.self) { route in
            ReleaseDetailView(releaseId: route.id)
        }
    }
}

struct PosterImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 10

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                ZStack {
                    Theme.card
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            default:
                ZStack {
                    Theme.card
                    ProgressView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct GradeBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill").font(.system(size: 9))
            Text(text).font(.caption2.bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct ReleaseCard: View {
    let release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: release.imageURL)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let g = release.gradeText { GradeBadge(text: g).padding(6) }
                }
            Text(release.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
            Text(release.episodesText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ReleaseRow: View {
    let release: Release

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(url: release.imageURL, cornerRadius: 8)
                .frame(width: 72, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text(release.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let original = release.titleOriginal {
                    Text(original).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let y = release.year { Text(y) }
                    if let c = release.category?.name { Text("· \(c)") }
                    if let s = release.status?.name { Text("· \(s)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(release.episodesText)
                    if let g = release.gradeText { Label(g, systemImage: "star.fill") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct ReleaseGrid: View {
    let releases: [Release]
    var onAppearLast: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 180), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(releases) { release in
                NavigationLink(value: ReleaseRoute(id: release.id)) {
                    ReleaseCard(release: release)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if release.id == releases.last?.id { onAppearLast?() }
                }
            }
        }
    }
}

struct HorizontalReleases: View {
    let title: String
    let releases: [Release]

    var body: some View {
        if !releases.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(releases) { release in
                            NavigationLink(value: ReleaseRoute(id: release.id)) {
                                ReleaseCard(release: release).frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Повторить", action: retry).buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

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
