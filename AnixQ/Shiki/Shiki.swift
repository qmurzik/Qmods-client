import Foundation
import SwiftUI
import UserNotifications

// MARK: - Session

/// Shikimori only issues tokens to registered OAuth applications, so the user registers their
/// own (free, one minute) and pastes its id/secret once.
enum ShikiSession {
    static let redirectURI = "urn:ietf:wg:oauth:2.0:oob"
    private static let d = UserDefaults.standard

    static var clientId: String? {
        get { d.string(forKey: "shiki.clientId") }
        set { d.set(newValue, forKey: "shiki.clientId") }
    }
    static var clientSecret: String? {
        get { d.string(forKey: "shiki.clientSecret") }
        set { d.set(newValue, forKey: "shiki.clientSecret") }
    }
    static var appName: String {
        get { d.string(forKey: "shiki.appName") ?? "AnixQ" }
        set { d.set(newValue, forKey: "shiki.appName") }
    }
    static var token: String? {
        get { d.string(forKey: "shiki.token") }
        set { d.set(newValue, forKey: "shiki.token") }
    }
    static var refreshToken: String? {
        get { d.string(forKey: "shiki.refresh") }
        set { d.set(newValue, forKey: "shiki.refresh") }
    }
    static var userId: Int? {
        get { d.object(forKey: "shiki.userId") as? Int }
        set { d.set(newValue, forKey: "shiki.userId") }
    }
    static var nickname: String? {
        get { d.string(forKey: "shiki.nickname") }
        set { d.set(newValue, forKey: "shiki.nickname") }
    }
    static var isLoggedIn: Bool { token != nil && userId != nil }

    static func clear() {
        token = nil
        refreshToken = nil
        userId = nil
        nickname = nil
    }
}

// MARK: - Models

struct ShikiCalendarItem: Identifiable, Hashable {
    let shikiId: Int
    let name: String
    let russian: String?
    let image: URL?
    let kind: String?
    let score: Double?
    let episodesAired: Int?
    let episodes: Int?
    let nextEpisode: Int
    let nextEpisodeAt: Date

    var id: String { "\(shikiId)-\(nextEpisode)" }
    var title: String { russian?.nilIfEmpty ?? name }
}

struct ShikiAnimeInfo {
    let score: Double?
    let episodes: Int?
    let episodesAired: Int?
    let nextEpisodeAt: Date?
    let status: String?
}

// MARK: - API

enum ShikiAPI {
    static let host = "https://shikimori.io"

    static let dateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return dateParser.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    static func request(_ path: String, method: String = "GET", json: Any? = nil, form: [String: String]? = nil,
                        auth: Bool = true) async throws -> Any {
        var req = URLRequest(url: URL(string: host + path)!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(ShikiSession.appName, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let form {
            req.httpBody = form.map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)" }
                .joined(separator: "&").data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if auth, let token = ShikiSession.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, auth, await refresh() {
            return try await request(path, method: method, json: json, form: form, auth: auth)
        }
        guard (200..<300).contains(status) else {
            DebugLog.log("shiki: \(method) \(path) -> \(status) \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
            throw LibError.badStatus(status)
        }
        if data.isEmpty { return JSON() }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: Public data

    static func calendar() async throws -> [ShikiCalendarItem] {
        let json = try await request("/api/calendar", auth: false)
        return (json as? [JSON] ?? []).compactMap { x -> ShikiCalendarItem? in
            guard let a = x.obj("anime"), let id = a.int("id"),
                  let at = parseDate(x.str("next_episode_at")) else { return nil }
            // The API hides posters behind "missing" placeholders; the direct path still works.
            let img = a.obj("image")?.str("original").flatMap { path -> URL? in
                path.contains("missing") ? URL(string: "\(host)/system/animes/preview/\(id).jpg") : URL(string: host + path)
            }
            return ShikiCalendarItem(shikiId: id, name: a.str("name") ?? "", russian: a.str("russian"), image: img,
                                     kind: a.str("kind"), score: a.double("score"),
                                     episodesAired: a.int("episodes_aired"), episodes: a.int("episodes"),
                                     nextEpisode: x.int("next_episode") ?? 0, nextEpisodeAt: at)
        }
    }

    static func anime(_ id: Int) async throws -> ShikiAnimeInfo {
        let x = try await request("/api/animes/\(id)", auth: false) as? JSON ?? [:]
        return ShikiAnimeInfo(score: x.double("score"), episodes: x.int("episodes"),
                              episodesAired: x.int("episodes_aired"),
                              nextEpisodeAt: parseDate(x.str("next_episode_at")), status: x.str("status"))
    }

    // MARK: OAuth

    static func authorizeURL() -> URL? {
        guard let id = ShikiSession.clientId else { return nil }
        var c = URLComponents(string: host + "/oauth/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: ShikiSession.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "user_rates")
        ]
        return c.url
    }

    static func exchange(code: String) async throws {
        guard let id = ShikiSession.clientId, let secret = ShikiSession.clientSecret else { throw LibError.unauthorized }
        let json = try await request("/oauth/token", method: "POST", form: [
            "grant_type": "authorization_code", "client_id": id, "client_secret": secret,
            "code": code, "redirect_uri": ShikiSession.redirectURI
        ], auth: false) as? JSON ?? [:]
        guard let access = json.str("access_token") else { throw LibError.server("Shikimori не выдал токен") }
        ShikiSession.token = access
        ShikiSession.refreshToken = json.str("refresh_token")
        let me = try await request("/api/users/whoami") as? JSON ?? [:]
        ShikiSession.userId = me.int("id")
        ShikiSession.nickname = me.str("nickname")
        DebugLog.log("shiki: signed in as \(ShikiSession.nickname ?? "?")")
    }

    private static func refresh() async -> Bool {
        guard let id = ShikiSession.clientId, let secret = ShikiSession.clientSecret,
              let refresh = ShikiSession.refreshToken,
              let json = try? await request("/oauth/token", method: "POST", form: [
                "grant_type": "refresh_token", "client_id": id, "client_secret": secret, "refresh_token": refresh
              ], auth: false) as? JSON,
              let access = json.str("access_token") else { return false }
        ShikiSession.token = access
        if let r = json.str("refresh_token") { ShikiSession.refreshToken = r }
        return true
    }

    // MARK: User rates

    static func userRate(animeId: Int) async throws -> JSON? {
        guard let uid = ShikiSession.userId else { return nil }
        let json = try await request("/api/v2/user_rates?user_id=\(uid)&target_id=\(animeId)&target_type=Anime")
        return (json as? [JSON])?.first
    }

    static func upsertRate(animeId: Int, status: String?, episodes: Int?, score: Int? = nil) async throws {
        guard let uid = ShikiSession.userId else { return }
        var fields: JSON = [:]
        if let status { fields["status"] = status }
        if let episodes { fields["episodes"] = episodes }
        if let score { fields["score"] = score }
        if let existing = try await userRate(animeId: animeId), let rid = existing.int("id") {
            if let e = episodes, let have = existing.int("episodes"), have >= e, status == nil || status == existing.str("status") {
                return
            }
            _ = try await request("/api/v2/user_rates/\(rid)", method: "PATCH", json: ["user_rate": fields])
        } else {
            fields["user_id"] = uid
            fields["target_id"] = animeId
            fields["target_type"] = "Anime"
            if fields["status"] == nil { fields["status"] = "watching" }
            _ = try await request("/api/v2/user_rates", method: "POST", json: ["user_rate": fields])
        }
    }
}

// MARK: - Sync

@MainActor
final class ShikiSync: ObservableObject {
    static let shared = ShikiSync()
    @Published var isLoggedIn = ShikiSession.isLoggedIn
    @Published var lastError: String?

    func refreshState() { isLoggedIn = ShikiSession.isLoggedIn }

    func episodeWatched(title: Title, episodes: Int, completed: Bool) async {
        guard ShikiSession.isLoggedIn, let id = title.shikiId else { return }
        do {
            try await ShikiAPI.upsertRate(animeId: id, status: completed ? "completed" : "watching", episodes: episodes)
            DebugLog.log("shiki: \(title.title) -> \(episodes) эп.\(completed ? " (completed)" : "")")
            lastError = nil
        } catch {
            lastError = "Shikimori: \(error.localizedDescription)"
        }
    }

    func setStatus(title: Title, status: BookmarkStatus) async {
        guard ShikiSession.isLoggedIn, let id = title.shikiId else { return }
        do {
            try await ShikiAPI.upsertRate(animeId: id, status: status.shikiStatus, episodes: nil)
        } catch {
            lastError = "Shikimori: \(error.localizedDescription)"
        }
    }

    func rate(title: Title, score: Int) async {
        guard ShikiSession.isLoggedIn, let id = title.shikiId else { return }
        try? await ShikiAPI.upsertRate(animeId: id, status: nil, episodes: nil, score: score)
    }
}

// MARK: - New-episode notifications

/// Schedules a local notification for the next episode of every title in "Смотрю",
/// using Shikimori's `next_episode_at`. Re-run on every app launch / foreground.
@MainActor
enum EpisodeNotifier {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notify.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notify.enabled") }
    }

    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isEnabled = granted
        return granted
    }

    static func reschedule(titles: [Title]) async {
        let center = UNUserNotificationCenter.current()
        guard isEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }
        center.removeAllPendingNotificationRequests()
        var scheduled = 0
        for title in titles.prefix(40) {
            guard let sid = title.shikiId, let info = try? await ShikiAPI.anime(sid),
                  let at = info.nextEpisodeAt, at > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = title.title
            let next = (info.episodesAired ?? 0) + 1
            content.body = "Вышла \(next)-я серия. Озвучки обычно появляются в течение нескольких часов."
            content.sound = .default
            content.userInfo = ["slug": title.slugURL]
            // Dubs usually land a little after the Japanese air time.
            let fire = at.addingTimeInterval(2 * 3600)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: "ep-\(title.id)-\(next)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
            scheduled += 1
        }
        DebugLog.log("notify: scheduled \(scheduled) episode notifications")
    }
}
