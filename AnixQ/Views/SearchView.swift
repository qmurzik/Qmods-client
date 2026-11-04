import SwiftUI

struct SearchView: View {
    @StateObject private var pager = PagedReleases()
    @State private var query = ""
    @State private var submitted = ""
    @AppStorage("search.recent") private var recentRaw = ""

    private var recent: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    var body: some View {
        List {
            if submitted.isEmpty {
                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { q in
                            Button {
                                query = q
                                submit()
                            } label: {
                                Label(q, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Недавние")
                            Spacer()
                            Button("Очистить") { recentRaw = "" }.font(.caption)
                        }
                    }
                } else {
                    Text("Введите название аниме на русском, английском или японском")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(pager.items) { release in
                    NavigationLink(value: ReleaseRoute(id: release.id)) {
                        ReleaseRow(release: release)
                    }
                    .onAppear {
                        if release.id == pager.items.last?.id { Task { await pager.loadMore() } }
                    }
                }
                if pager.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = pager.error {
                    ErrorView(message: error) { submit() }
                } else if pager.items.isEmpty {
                    Text("Ничего не найдено").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Поиск")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название аниме")
        .onSubmit(of: .search) { submit() }
        .onChange(of: query) { newValue in
            if newValue.isEmpty { submitted = "" }
        }
        .releaseDestinations()
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        submitted = q
        var list = recent.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        recentRaw = list.prefix(10).joined(separator: "\n")
        Task {
            await pager.reset { page in try await AnixartAPI.shared.search(q, page: page) }
        }
    }
}
