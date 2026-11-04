import SwiftUI

@MainActor
final class ReleaseModel: ObservableObject {
    @Published var release: Release?
    @Published var error: String?
    @Published var isFavorite = false
    @Published var listStatus: Int?

    let releaseId: Int
    private let api = AnixartAPI.shared

    init(releaseId: Int) { self.releaseId = releaseId }

    func load() async {
        error = nil
        do {
            let r = try await api.release(releaseId)
            release = r
            isFavorite = r.isFavorite
            listStatus = (r.profileListStatus ?? 0) > 0 ? r.profileListStatus : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleFavorite() async {
        let target = !isFavorite
        do {
            if target { try await api.addFavorite(releaseId: releaseId) }
            else { try await api.removeFavorite(releaseId: releaseId) }
            isFavorite = target
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setList(_ list: WatchList?) async {
        do {
            if let list {
                try await api.addToList(list, releaseId: releaseId)
            } else if let current = listStatus.flatMap(WatchList.init(rawValue:)) {
                try await api.removeFromList(current, releaseId: releaseId)
            }
            listStatus = list?.rawValue
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ReleaseDetailView: View {
    @StateObject private var model: ReleaseModel
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: HistoryStore
    @State private var expanded = false
    @State private var showLogin = false

    init(releaseId: Int) {
        _model = StateObject(wrappedValue: ReleaseModel(releaseId: releaseId))
    }

    var body: some View {
        Group {
            if let release = model.release {
                content(release)
            } else if let error = model.error {
                ErrorView(message: error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.release == nil { await model.load() } }
        .sheet(isPresented: $showLogin) { LoginView() }
    }

    @ViewBuilder
    private func content(_ r: Release) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(r)
                actions(r)
                if let note = r.note, !note.isEmpty {
                    Text(note.strippingHTML)
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                if let d = r.description, !d.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Описание").font(.headline)
                        Text(d).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(expanded ? nil : 5)
                        Button(expanded ? "Свернуть" : "Подробнее") {
                            withAnimation { expanded.toggle() }
                        }
                        .font(.footnote)
                    }
                }
                infoTable(r)
                if !r.screenshotImages.isEmpty { screenshots(r) }
            }
            .padding()

            VStack(alignment: .leading, spacing: 24) {
                HorizontalReleases(title: "Связанные", releases: r.related.filter { $0.id != r.id })
                HorizontalReleases(title: "Рекомендации", releases: r.recommended)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(r.title)
        .navigationDestination(for: EpisodesRoute.self) { route in
            VoiceoverPickerView(release: route.release)
        }
    }

    private func header(_ r: Release) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PosterImage(url: r.imageURL, cornerRadius: 12)
                .frame(width: 130, height: 190)
            VStack(alignment: .leading, spacing: 6) {
                Text(r.title).font(.title3.bold())
                if let o = r.titleOriginal { Text(o).font(.footnote).foregroundStyle(.secondary) }
                if let g = r.gradeText {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(g).bold()
                        if let v = r.voteCount { Text("(\(v))").foregroundStyle(.secondary) }
                    }
                    .font(.subheadline)
                }
                Text([r.category?.name, r.status?.name, r.year].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Text(r.episodesText).font(.caption).foregroundStyle(.secondary)
                if let a = r.ageText {
                    Text(a).font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(.secondary))
                }
            }
        }
    }

    private func actions(_ r: Release) -> some View {
        VStack(spacing: 10) {
            NavigationLink(value: EpisodesRoute(release: r)) {
                Label(continueTitle(r), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(r.isPlayDisabled)

            HStack(spacing: 10) {
                Menu {
                    ForEach(WatchList.allCases) { list in
                        Button {
                            Task { await model.setList(list) }
                        } label: {
                            if model.listStatus == list.rawValue {
                                Label(list.title, systemImage: "checkmark")
                            } else {
                                Label(list.title, systemImage: list.icon)
                            }
                        }
                    }
                    if model.listStatus != nil {
                        Button("Убрать из списков", role: .destructive) {
                            Task { await model.setList(nil) }
                        }
                    }
                } label: {
                    Label(model.listStatus.flatMap(WatchList.init(rawValue:))?.title ?? "В список",
                          systemImage: "bookmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!auth.isLoggedIn)

                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    Label("Избранное", systemImage: model.isFavorite ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!auth.isLoggedIn)
            }
            if !auth.isLoggedIn {
                Button("Войдите в Anixart, чтобы пользоваться списками") { showLogin = true }
                    .font(.caption)
            }
            if r.isPlayDisabled {
                Text("Просмотр этого релиза недоступен в вашем регионе")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func continueTitle(_ r: Release) -> String {
        if let last = history.last(for: r.id) { return "Продолжить: \(last.episodeName)" }
        return "Смотреть"
    }

    private func infoTable(_ r: Release) -> some View {
        let rows: [(String, String?)] = [
            ("Жанры", r.genres),
            ("Студия", r.studio),
            ("Страна", r.country),
            ("Сезон", [r.seasonText, r.year].compactMap { $0 }.joined(separator: " ").nilIfEmpty),
            ("Длительность", r.duration.map { "\($0) мин." }),
            ("Режиссёр", r.director),
            ("Автор", r.author),
            ("Первоисточник", r.source),
            ("Озвучка", r.translators)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.filter { ($0.1 ?? "").isEmpty == false }, id: \.0) { row in
                HStack(alignment: .top) {
                    Text(row.0).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                    Text(row.1 ?? "")
                    Spacer(minLength: 0)
                }
                .font(.footnote)
            }
        }
    }

    private func screenshots(_ r: Release) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Кадры").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(r.screenshotImages, id: \.self) { s in
                        PosterImage(url: URL(string: s), cornerRadius: 10)
                            .frame(width: 220, height: 124)
                    }
                }
            }
        }
    }
}

struct EpisodesRoute: Hashable {
    let release: Release
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var strippingHTML: String {
        replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
