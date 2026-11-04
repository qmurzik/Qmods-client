import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var profileName: String?
    @Published private(set) var isLoggedIn: Bool

    private let api = AnixartAPI.shared

    init() {
        isLoggedIn = api.token != nil
        profileName = UserDefaults.standard.string(forKey: "anixart.login")
    }

    func signIn(login: String, password: String) async throws {
        let r = try await api.signIn(login: login, password: password)
        guard r.code == 0, let token = r.token else {
            switch r.code {
            case 2: throw AuthError.wrongLogin
            case 3: throw AuthError.wrongPassword
            default: throw AuthError.other(r.code)
            }
        }
        api.token = token
        let name = r.profile?.login ?? login
        UserDefaults.standard.set(name, forKey: "anixart.login")
        profileName = name
        isLoggedIn = true
    }

    func signOut() {
        api.token = nil
        UserDefaults.standard.removeObject(forKey: "anixart.login")
        profileName = nil
        isLoggedIn = false
    }

    enum AuthError: LocalizedError {
        case wrongLogin, wrongPassword, other(Int)
        var errorDescription: String? {
            switch self {
            case .wrongLogin: return "Пользователь не найден"
            case .wrongPassword: return "Неверный пароль"
            case .other(let c): return "Не удалось войти (код \(c))"
            }
        }
    }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    let releaseId: Int
    var title: String
    var image: String?
    var episodePosition: Int
    var episodeName: String
    var typeId: Int
    var typeName: String
    var sourceId: Int
    var date: Date

    var id: Int { releaseId }
}

/// Local, on-device watch history. Works without an Anixart account.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var watched: [Int: Set<Int>] = [:]   // releaseId -> watched positions

    private let historyKey = "history.entries"
    private let watchedKey = "history.watched"

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: watchedKey),
           let decoded = try? JSONDecoder().decode([Int: Set<Int>].self, from: data) {
            watched = decoded
        }
    }

    func record(release: Release, episode: Episode, type: VoiceoverType) {
        let entry = HistoryEntry(releaseId: release.id, title: release.title, image: release.image,
                                 episodePosition: episode.position, episodeName: episode.name,
                                 typeId: type.id, typeName: type.name, sourceId: episode.sourceId, date: Date())
        entries.removeAll { $0.releaseId == release.id }
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        watched[release.id, default: []].insert(episode.position)
        persist()
    }

    func isWatched(releaseId: Int, position: Int) -> Bool {
        watched[releaseId]?.contains(position) ?? false
    }

    func toggleWatched(releaseId: Int, position: Int) {
        if watched[releaseId]?.contains(position) == true {
            watched[releaseId]?.remove(position)
        } else {
            watched[releaseId, default: []].insert(position)
        }
        persist()
    }

    func last(for releaseId: Int) -> HistoryEntry? {
        entries.first { $0.releaseId == releaseId }
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.releaseId == entry.releaseId }
        persist()
    }

    func clear() {
        entries = []
        watched = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
        if let data = try? JSONEncoder().encode(watched) {
            UserDefaults.standard.set(data, forKey: watchedKey)
        }
    }
}
