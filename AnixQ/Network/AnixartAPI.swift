import Foundation

enum APIError: LocalizedError {
    case badStatus(Int)
    case server(code: Int)
    case unauthorized
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .badStatus(let s): return "Сервер ответил ошибкой \(s)"
        case .server(let code): return "Ошибка Anixart (код \(code))"
        case .unauthorized: return "Нужно войти в аккаунт Anixart"
        case .decoding: return "Не удалось разобрать ответ сервера"
        case .transport(let e): return e.localizedDescription
        }
    }
}

/// Sort orders accepted by `/filter/{page}`.
enum CatalogSort: Int, CaseIterable, Identifiable {
    case updated = 0, rating = 1, popular = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .updated: return "Новые серии"
        case .rating: return "По рейтингу"
        case .popular: return "Популярное"
        }
    }
}

enum CatalogCategory: Int, CaseIterable, Identifiable {
    case all = 0, series = 1, movie = 2, ova = 3, special = 6

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .series: return "Сериалы"
        case .movie: return "Фильмы"
        case .ova: return "OVA"
        case .special: return "Спешлы"
        }
    }
}

enum CatalogStatus: Int, CaseIterable, Identifiable {
    case all = 0, finished = 1, ongoing = 2, announce = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .all: return "Любой"
        case .finished: return "Вышел"
        case .ongoing: return "Выходит"
        case .announce: return "Анонс"
        }
    }
}

struct CatalogFilter: Equatable {
    var sort: CatalogSort = .updated
    var category: CatalogCategory = .all
    var status: CatalogStatus = .all
    var genres: Set<String> = []
    var fromYear: Int? = nil
    var toYear: Int? = nil

    static let allGenres = [
        "боевые искусства", "война", "драма", "детектив", "история", "комедия", "меха", "мистика",
        "музыка", "повседневность", "приключения", "психологическое", "романтика", "сверхъестественное",
        "спорт", "триллер", "ужасы", "фантастика", "фэнтези", "школа", "экшен", "исекай", "сёнэн",
        "сёдзё", "сэйнэн", "дзёсэй", "киберпанк", "магия", "демоны", "вампиры", "игры", "гарем", "пародия"
    ]

    var body: [String: Any] {
        var b: [String: Any] = [
            "sort": sort.rawValue,
            "genres": Array(genres),
            "is_genres_exclude_mode_enabled": false,
            "profile_list_exclusions": [Int](),
            "types": [Int](),
            "age_ratings": [Int]()
        ]
        if category != .all { b["category_id"] = category.rawValue }
        if status != .all { b["status_id"] = status.rawValue }
        if let fromYear { b["start_year"] = fromYear }
        if let toYear { b["end_year"] = toYear }
        return b
    }
}

final class AnixartAPI {
    static let shared = AnixartAPI()

    /// Official API host plus known mirrors (used as fallbacks when the main host is blocked).
    static let hosts = ["https://api.anixart.tv", "https://api-s2.anixart.tv", "https://api.anixsekai.com"]

    private let session: URLSession
    private let userAgent = "AnixartApp/9.0 BETA 5-25062213 (Android 9; SDK 28; arm64-v8a; samsung SM-G975N; en)"
    private var hostIndex = 0

    var token: String? {
        get { UserDefaults.standard.string(forKey: "anixart.token") }
        set { UserDefaults.standard.set(newValue, forKey: "anixart.token") }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: config)
    }

    // MARK: Transport

    private func makeRequest(host: String, path: String, query: [URLQueryItem], method: String,
                             body: Data?, contentType: String?) -> URLRequest {
        var comps = URLComponents(string: host + path)!
        var items = query
        if let token { items.append(URLQueryItem(name: "token", value: token)) }
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        return req
    }

    private func send<T: Decodable>(_ path: String, query: [URLQueryItem] = [], method: String = "GET",
                                    body: Data? = nil, contentType: String? = nil) async throws -> T {
        var lastError: Error = APIError.badStatus(0)
        for attempt in 0..<Self.hosts.count {
            let idx = (hostIndex + attempt) % Self.hosts.count
            let req = makeRequest(host: Self.hosts[idx], path: path, query: query, method: method,
                                  body: body, contentType: contentType)
            do {
                let (data, response) = try await session.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    lastError = APIError.badStatus(status)
                    if status >= 500 { continue }
                    throw lastError
                }
                hostIndex = idx
                if let codeOnly = try? JSONDecoder().decode(CodeResponse.self, from: data), codeOnly.code == 401 {
                    throw APIError.unauthorized
                }
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw APIError.decoding(error)
                }
            } catch let e as APIError {
                throw e
            } catch {
                if (error as? URLError)?.code == .cancelled { throw error }
                lastError = APIError.transport(error)
            }
        }
        throw lastError
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path, query: query)
    }

    private func postJSON<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(path, method: "POST", body: data, contentType: "application/json; charset=UTF-8")
    }

    private func postForm<T: Decodable>(_ path: String, _ fields: [String: String]) async throws -> T {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
        return try await send(path, method: "POST", body: Data(body.utf8),
                              contentType: "application/x-www-form-urlencoded")
    }

    // MARK: Catalog

    func interesting() async throws -> [InterestingItem] {
        let r: InterestingResponse = try await get("/discover/interesting")
        return r.content
    }

    func discussing() async throws -> [Release] {
        let r: Page<Release> = try await postJSON("/discover/discussing", [:])
        return r.content
    }

    func filter(_ filter: CatalogFilter, page: Int) async throws -> Page<Release> {
        try await postJSON("/filter/\(page)", filter.body)
    }

    func search(_ query: String, page: Int) async throws -> Page<Release> {
        try await postJSON("/search/releases/\(page)", ["query": query, "searchBy": 0])
    }

    func release(_ id: Int) async throws -> Release {
        let r: ReleaseResponse = try await get("/release/\(id)")
        guard let release = r.release else { throw APIError.server(code: r.code) }
        return release
    }

    func randomRelease() async throws -> Release {
        let r: ReleaseResponse = try await get("/release/random")
        guard let release = r.release else { throw APIError.server(code: r.code) }
        return release
    }

    func schedule() async throws -> ScheduleResponse {
        try await get("/schedule")
    }

    // MARK: Episodes

    func voiceovers(releaseId: Int) async throws -> [VoiceoverType] {
        let r: TypesResponse = try await get("/episode/\(releaseId)")
        return r.types
    }

    func sources(releaseId: Int, typeId: Int) async throws -> [EpisodeSource] {
        let r: SourcesResponse = try await get("/episode/\(releaseId)/\(typeId)")
        return r.sources
    }

    func episodes(releaseId: Int, typeId: Int, sourceId: Int) async throws -> [Episode] {
        let r: EpisodesResponse = try await get("/episode/\(releaseId)/\(typeId)/\(sourceId)", query: [
            URLQueryItem(name: "sort", value: "1")
        ])
        return r.episodes.sorted { $0.position < $1.position }
    }

    // MARK: Account

    func signIn(login: String, password: String) async throws -> SignInResponse {
        try await postForm("/auth/signIn", ["login": login, "password": password])
    }

    func list(_ list: WatchList, page: Int) async throws -> Page<Release> {
        try await get("/profile/list/all/\(list.rawValue)/\(page)", query: [URLQueryItem(name: "sort", value: "1")])
    }

    func addToList(_ list: WatchList, releaseId: Int) async throws {
        let _: CodeResponse = try await get("/profile/list/add/\(list.rawValue)/\(releaseId)")
    }

    func removeFromList(_ list: WatchList, releaseId: Int) async throws {
        let _: CodeResponse = try await get("/profile/list/delete/\(list.rawValue)/\(releaseId)")
    }

    func favorites(page: Int) async throws -> Page<Release> {
        try await get("/favorite/all/\(page)", query: [URLQueryItem(name: "sort", value: "1")])
    }

    func addFavorite(releaseId: Int) async throws {
        let _: CodeResponse = try await get("/favorite/add/\(releaseId)")
    }

    func removeFavorite(releaseId: Int) async throws {
        let _: CodeResponse = try await get("/favorite/delete/\(releaseId)")
    }
}
