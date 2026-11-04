import SwiftUI

struct CatalogView: View {
    @StateObject private var pager = PagedReleases()
    @State private var filter = CatalogFilter()
    @State private var showFilter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterBar
                ReleaseGrid(releases: pager.items) {
                    Task { await pager.loadMore() }
                }
                .padding(.horizontal)

                if pager.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if let error = pager.error {
                    ErrorView(message: error) { Task { await reload() } }
                } else if pager.items.isEmpty {
                    EmptyStateView(icon: "sparkle.magnifyingglass", text: "По этим фильтрам ничего нет")
                }
            }
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Каталог")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showFilter = true } label: {
                    Image(systemName: activeFilters > 0 ? "slider.horizontal.3" : "slider.horizontal.3")
                        .overlay(alignment: .topTrailing) {
                            if activeFilters > 0 {
                                Text("\(activeFilters)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(3)
                                    .background(Theme.accent, in: Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(filter: $filter)
                .presentationDetents([.medium, .large])
        }
        .releaseDestinations()
        .refreshable { await reload() }
        .task { if pager.items.isEmpty { await reload() } }
        .onChange(of: filter) { _ in Task { await reload() } }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Сортировка", selection: $filter.sort) {
                        ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    chip(filter.sort.title, icon: "arrow.up.arrow.down", active: true)
                }
                ForEach(CatalogCategory.allCases.filter { $0 != .all }) { c in
                    Button {
                        filter.category = filter.category == c ? .all : c
                    } label: {
                        chip(c.title, active: filter.category == c)
                    }
                }
                Divider().frame(height: 22)
                ForEach(CatalogStatus.allCases.filter { $0 != .all }) { s in
                    Button {
                        filter.status = filter.status == s ? .all : s
                    } label: {
                        chip(s.title, active: filter.status == s)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, icon: String? = nil, active: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card), in: Capsule())
        .overlay(Capsule().stroke(active ? Color.clear : Theme.stroke))
        .foregroundStyle(.white)
    }

    private var activeFilters: Int {
        var n = filter.genres.count
        if filter.fromYear != nil || filter.toYear != nil { n += 1 }
        return n
    }

    private func reload() async {
        let f = filter
        await pager.reset { page in try await AnixartAPI.shared.filter(f, page: page) }
    }
}

struct FilterSheet: View {
    @Binding var filter: CatalogFilter
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CatalogFilter()

    private let years = Array((1960...Calendar.current.component(.year, from: Date()) + 1).reversed())
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Годы") {
                        HStack {
                            yearMenu("С", selection: $draft.fromYear)
                            yearMenu("По", selection: $draft.toYear)
                        }
                    }
                    group("Жанры") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(CatalogFilter.allGenres, id: \.self) { genre in
                                let on = draft.genres.contains(genre)
                                Button {
                                    if on { draft.genres.remove(genre) } else { draft.genres.insert(genre) }
                                } label: {
                                    Text(genre.capitalized)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        draft.genres = []
                        draft.fromYear = nil
                        draft.toYear = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        filter = draft
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .onAppear { draft = filter }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func yearMenu(_ label: String, selection: Binding<Int?>) -> some View {
        Menu {
            Picker(label, selection: selection) {
                Text("Любой").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
        } label: {
            HStack {
                Text(label).foregroundStyle(Theme.secondaryText)
                Text(selection.wrappedValue.map(String.init) ?? "любой").bold()
                Spacer()
                Image(systemName: "chevron.down").font(.caption)
            }
            .padding(12)
            .cardStyle(radius: 12)
            .foregroundStyle(.white)
        }
    }
}
