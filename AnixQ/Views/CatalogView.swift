import SwiftUI

struct CatalogView: View {
    @StateObject private var pager = PagedReleases()
    @State private var filter = CatalogFilter()
    @State private var showFilter = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Сортировка", selection: $filter.sort) {
                    ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                ReleaseGrid(releases: pager.items) {
                    Task { await pager.loadMore() }
                }

                if pager.isLoading {
                    ProgressView().padding()
                } else if let error = pager.error {
                    ErrorView(message: error) { Task { await reload() } }
                } else if pager.items.isEmpty {
                    Text("Ничего не найдено").foregroundStyle(.secondary).padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Каталог")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showFilter = true } label: {
                    Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill"
                                                 : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(filter: $filter)
        }
        .releaseDestinations()
        .refreshable { await reload() }
        .task { if pager.items.isEmpty { await reload() } }
        .onChange(of: filter) { _ in Task { await reload() } }
    }

    private var isFiltered: Bool {
        filter.category != .all || filter.status != .all || !filter.genres.isEmpty
            || filter.fromYear != nil || filter.toYear != nil
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Тип") {
                    Picker("Категория", selection: $draft.category) {
                        ForEach(CatalogCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Статус", selection: $draft.status) {
                        ForEach(CatalogStatus.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Год") {
                    Picker("С", selection: $draft.fromYear) {
                        Text("Любой").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                    Picker("По", selection: $draft.toYear) {
                        Text("Любой").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                }
                Section("Жанры") {
                    ForEach(CatalogFilter.allGenres, id: \.self) { genre in
                        Button {
                            if draft.genres.contains(genre) { draft.genres.remove(genre) }
                            else { draft.genres.insert(genre) }
                        } label: {
                            HStack {
                                Text(genre.capitalized).foregroundStyle(.primary)
                                Spacer()
                                if draft.genres.contains(genre) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Фильтр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        draft = CatalogFilter(sort: filter.sort)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        filter = draft
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = filter }
    }
}
