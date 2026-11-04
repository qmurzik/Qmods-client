import Foundation

// MARK: - Models

struct LibAnime: Identifiable, Hashable {
    let id: Int
    let slugURL: String
    let rusName: String?
    let name: String?
    let engName: String?
    let year: Int?
}

struct LibEpisode: Identifiable, Hashable {
    let id: Int
    let number: String
    let name: String?
    let itemNumber: Int
}

struct LibTeam: Hashable {
    let id: Int
    let name: String
    let isSubtitles: Bool
}

struct LibPlayer: Hashable {
    let team: LibTeam
    let player: String               // "Animelib" | "Kodik" | ...
    let kodikSrc: String?
    let qualities: [(label: String, href: String)]

    static func == (l: LibPlayer, r: LibPlayer) -> Bool {
        l.team == r.team && l.player == r.player && l.kodikSrc == r.kodikSrc
    }
    func hash(into h: inout Hasher) { h.combine(team); h.combine(player); h.combine(kodikSrc) }

    var isNative: Bool { player.lowercased() == "animelib" && !qualities.isEmpty }
}

// MARK: - Token storage

enum AnimeLibSession {
    private static let tokenKey = "animelib.token"
    private static let refreshKey = "animelib.refresh"
    private static let nameKey = "animelib.username"

    static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
    static var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshKey) }
    }
    static var username: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }
    static var isLoggedIn: Bool { token != nil }

    static func clear() {
        token = nil
        refreshToken = nil
        username = nil
    }
}

// MARK: - API

/// Client for the public AnimeLib (lib.social) API used by anilib.me itself.
enum AnimeLibAPI {
    static let hosts = ["https://api.cdnlibs.org", "https://api.lib.social"]
    static let site = "https://anilib.me"
    private static let fallbackServers = ["https://video1.cdnlibs.org/.аs/", "https://video2.cdnlibs.org/",
                                          "https://video1.imglib.info/"]
    private static var cachedServers: [String]?

    enum LibError: LocalizedError {
        case notFound, unauthorized, noVideo
        var errorDescription: String? {
            switch self {
            case .notFound: return "Тайтл не найден на AnimeLib"
            case .unauthorized: return "Сессия AnimeLib истекла — войдите снова"
            case .noVideo: return "У этой озвучки нет видео для серии"
            }
        }
    }

    // MARK: Transport

    private static func request(_ path: String, query: [URLQueryItem] = [], auth: Bool = true,
                                method: String = "GET", body: Data? = nil) async throws -> Any {
        var lastError: Error = LibError.notFound
        for host in hosts {
            var comps = URLComponents(string: host + path)!
            if !query.isEmpty { comps.queryItems = query }
            var req = URLRequest(url: comps.url!)
            req.httpMethod = method
            req.httpBody = body
            req.timeoutInterval = 20
            req.setValue("5", forHTTPHeaderField: "Site-Id")
            req.setValue(site + "/", forHTTPHeaderField: "Referer")
            req.setValue(site, forHTTPHeaderField: "Origin")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
            if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            if auth, let token = AnimeLibSession.token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 {
                    if auth, AnimeLibSession.token != nil, await refresh() {
                        return try await request(path, query: query, auth: auth, method: method, body: body)
                    }
                    throw LibError.unauthorized
                }
                guard (200..<300).contains(status) else {
                    lastError = APIError.badStatus(status)
                    continue
                }
                return try JSONSerialization.jsonObject(with: data)
            } catch let e as LibError {
                throw e
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func refresh() async -> Bool {
        guard let refresh = AnimeLibSession.refreshToken else { return false }
        let body: [String: Any] = ["grant_type": "refresh_token", "client_id": 1,
                                   "refresh_token": refresh, "scope": ""]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = try? await request("/api/auth/oauth/token", auth: false, method: "POST", body: data)
                as? [String: Any],
              let access = json["access_token"] as? String else {
            return false
        }
        AnimeLibSession.token = access
        if let r = json["refresh_token"] as? String { AnimeLibSession.refreshToken = r }
        return true
    }

    static func me() async -> String? {
        guard let json = try? await request("/api/auth/me") as? [String: Any],
              let data = json["data"] as? [String: Any] else { return nil }
        return data["username"] as? String
    }

    // MARK: Catalog

    static func search(_ query: String) async throws -> [LibAnime] {
        let json = try await request("/api/anime", query: [URLQueryItem(name: "q", value: query)])
        let items = (json as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return items.compactMap { x in
            guard let id = x["id"] as? Int, let slug = x["slug_url"] as? String else { return nil }
            let date = x["releaseDateString"] as? String ?? ""
            let year = date.split(separator: " ").compactMap { Int($0) }.first { $0 > 1900 }
            return LibAnime(id: id, slugURL: slug, rusName: x["rus_name"] as? String, name: x["name"] as? String,
                            engName: x["eng_name"] as? String, year: year)
        }
    }

    /// Finds the AnimeLib entry for an Anixart release (title + year).
    static func match(_ release: Release) async throws -> LibAnime {
        let year = release.year.flatMap(Int.init)
        let queries = [release.titleOriginal, release.titleRu].compactMap { $0 }.filter { !$0.isEmpty }
        func norm(_ s: String?) -> String {
            (s ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        }
        var candidates: [LibAnime] = []
        for q in queries {
            let found = (try? await search(q)) ?? []
            let known = Set(candidates.map(\.id))
            let fresh = found.filter { !known.contains($0.id) }
            candidates.append(contentsOf: fresh)
            let targets = [release.titleOriginal, release.titleRu].map(norm)
            if let exact = found.first(where: { c in
                (year == nil || c.year == year) &&
                [c.name, c.rusName, c.engName].map(norm).contains(where: { !$0.isEmpty && targets.contains($0) })
            }) {
                return exact
            }
        }
        if let byYear = candidates.first(where: { year != nil && $0.year == year }) { return byYear }
        if let first = candidates.first { return first }
        throw LibError.notFound
    }

    static func episodes(slugURL: String) async throws -> [LibEpisode] {
        let json = try await request("/api/episodes", query: [URLQueryItem(name: "anime_id", value: slugURL)])
        let items = (json as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return items.compactMap { x in
            guard let id = x["id"] as? Int else { return nil }
            let number = (x["number"] as? String) ?? (x["number"] as? Int).map(String.init) ?? "?"
            return LibEpisode(id: id, number: number, name: x["name"] as? String,
                              itemNumber: x["item_number"] as? Int ?? Int(Double(number) ?? 0))
        }
    }

    private static var playerCache: [Int: (Date, [LibPlayer])] = [:]

    /// Player lists differ for guests and signed-in users, so they are dropped on login/logout.
    @MainActor
    static func clearCache() { playerCache = [:] }

    @MainActor
    static func players(episodeId: Int) async throws -> [LibPlayer] {
        if let hit = playerCache[episodeId], Date().timeIntervalSince(hit.0) < 600 { return hit.1 }
        let json = try await request("/api/episodes/\(episodeId)")
        let data = (json as? [String: Any])?["data"] as? [String: Any] ?? [:]
        let items = data["players"] as? [[String: Any]] ?? []
        let players: [LibPlayer] = items.compactMap { p in
            guard let teamObj = p["team"] as? [String: Any], let teamId = teamObj["id"] as? Int else { return nil }
            let tt = (p["translation_type"] as? [String: Any])?["id"] as? Int
            let team = LibTeam(id: teamId, name: teamObj["name"] as? String ?? "Команда", isSubtitles: tt == 1)
            let video = p["video"] as? [String: Any]
            var qualities: [(label: String, href: String)] = []
            for q in video?["quality"] as? [[String: Any]] ?? [] {
                guard let href = q["href"] as? String else { continue }
                let label = (q["quality"] as? Int).map { "\($0)p" } ?? (q["quality"] as? String).map { "\($0)p" } ?? "auto"
                qualities.append((label: label, href: href))
            }
            return LibPlayer(team: team, player: p["player"] as? String ?? "?",
                             kodikSrc: p["src"] as? String, qualities: qualities)
        }
        playerCache[episodeId] = (Date(), players)
        DebugLog.log("animelib: episode \(episodeId) players " +
                     players.map { "\($0.player)/\($0.team.name)" }.joined(separator: ", "))
        return players
    }

    // MARK: Video

    @MainActor
    static func videoServers() async -> [String] {
        if let cachedServers { return cachedServers }
        let json = try? await request("/api/constants", query: [URLQueryItem(name: "fields[]", value: "videoServers")])
        let list = (((json as? [String: Any])?["data"] as? [String: Any])?["videoServers"] as? [[String: Any]])?
            .compactMap { $0["url"] as? String } ?? []
        let servers = list.isEmpty ? fallbackServers : list
        cachedServers = servers
        return servers
    }

    /// Absolute, percent-encoded video URL (server URLs may contain non-ASCII path characters).
    static func videoURL(server: String, href: String) -> URL? {
        let base = server.hasSuffix("/") ? server : server + "/"
        let path = href.hasPrefix("/") ? String(href.dropFirst()) : href
        let raw = base + path
        if let url = URL(string: raw) { return url }
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        return URL(string: encoded)
    }

    static func kodikURL(_ src: String) -> URL? {
        URL(string: src.hasPrefix("//") ? "https:" + src : src)
    }
}
