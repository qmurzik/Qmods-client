import Foundation

// MARK: - Lossy decoding helpers
//
// Anixart's backend serialises with Jackson object identity ("@id"). An object that was
// already emitted earlier in the same response may be replaced by a bare integer
// reference, and field types are not always stable. Every model therefore decodes each
// field independently and tolerates missing / mismatched values instead of failing the
// whole response.

struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {}
}

struct LossyArray<T: Decodable>: Decodable {
    var items: [T]

    init(_ items: [T] = []) { self.items = items }

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            items = []
            return
        }
        var result: [T] = []
        while !container.isAtEnd {
            if let value = try? container.decode(T.self) {
                result.append(value)
            } else if (try? container.decode(AnyDecodable.self)) == nil {
                break
            }
        }
        items = result
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where K == DynamicKey {
    func value<T: Decodable>(_ key: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: DynamicKey(key))) ?? nil
    }

    func int(_ key: String) -> Int? {
        if let v: Int = value(key) { return v }
        if let s: String = value(key) { return Int(s) }
        if let d: Double = value(key) { return Int(d) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let v: Double = value(key) { return v }
        if let s: String = value(key) { return Double(s) }
        return nil
    }

    func string(_ key: String) -> String? {
        if let v: String = value(key) { return v }
        if let i: Int = value(key) { return String(i) }
        return nil
    }

    func array<T: Decodable>(_ key: String) -> [T] {
        (value(key) as LossyArray<T>?)?.items ?? []
    }
}

// MARK: - Common

struct NamedRef: Decodable, Hashable {
    let id: Int
    let name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        guard let id = c.int("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no id"))
        }
        self.id = id
        self.name = c.string("name") ?? ""
    }
}

struct Page<T: Decodable>: Decodable {
    let code: Int
    let content: [T]
    let totalCount: Int
    let totalPageCount: Int
    let currentPage: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        code = c.int("code") ?? 0
        content = c.array("content")
        totalCount = c.int("total_count") ?? 0
        totalPageCount = c.int("total_page_count") ?? 0
        currentPage = c.int("current_page") ?? 0
    }
}

// MARK: - Release

struct Release: Decodable, Identifiable, Hashable {
    let id: Int
    let titleRu: String?
    let titleOriginal: String?
    let titleAlt: String?
    let image: String?
    let year: String?
    let grade: Double?
    let status: NamedRef?
    let category: NamedRef?
    let episodesReleased: Int?
    let episodesTotal: Int?
    let genres: String?
    let description: String?
    let studio: String?
    let country: String?
    let director: String?
    let author: String?
    let source: String?
    let translators: String?
    let duration: Int?
    let ageRating: Int?
    let season: Int?
    let voteCount: Int?
    let screenshotImages: [String]
    let recommended: [Release]
    let related: [Release]
    let isFavorite: Bool
    let profileListStatus: Int?
    let isPlayDisabled: Bool
    let note: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        guard let id = c.int("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "release without id"))
        }
        self.id = id
        titleRu = c.string("title_ru")
        titleOriginal = c.string("title_original")
        titleAlt = c.string("title_alt")
        image = c.string("image")
        year = c.string("year")
        grade = c.double("grade")
        status = c.value("status")
        category = c.value("category")
        episodesReleased = c.int("episodes_released")
        episodesTotal = c.int("episodes_total")
        genres = c.string("genres")
        description = c.string("description")
        studio = c.string("studio")
        country = c.string("country")
        director = c.string("director")
        author = c.string("author")
        source = c.string("source")
        translators = c.string("translators")
        duration = c.int("duration")
        ageRating = c.int("age_rating")
        season = c.int("season")
        voteCount = c.int("vote_count")
        screenshotImages = c.array("screenshot_images")
        recommended = c.array("recommended_releases")
        related = c.array("related_releases")
        isFavorite = c.value("is_favorite") ?? false
        profileListStatus = c.int("profile_list_status")
        isPlayDisabled = c.value("is_play_disabled") ?? false
        note = c.string("note")
    }

    static func == (lhs: Release, rhs: Release) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var title: String { titleRu ?? titleOriginal ?? "Без названия" }
    var imageURL: URL? { image.flatMap(URL.init(string:)) }

    var episodesText: String {
        let released = episodesReleased.map(String.init) ?? "?"
        let total = episodesTotal.map(String.init) ?? "?"
        return "\(released) из \(total) эп."
    }

    var gradeText: String? {
        guard let grade, grade > 0 else { return nil }
        return String(format: "%.1f", grade)
    }

    var seasonText: String? {
        switch season {
        case 1: return "Зима"
        case 2: return "Весна"
        case 3: return "Лето"
        case 4: return "Осень"
        default: return nil
        }
    }

    var ageText: String? {
        switch ageRating {
        case 1: return "0+"
        case 2: return "6+"
        case 3: return "12+"
        case 4: return "16+"
        case 5: return "18+"
        default: return nil
        }
    }
}

struct ReleaseResponse: Decodable {
    let code: Int
    let release: Release?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        code = c.int("code") ?? 0
        release = c.value("release")
    }
}

// MARK: - Discover

struct InterestingItem: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let image: String?
    let type: Int
    let action: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        id = c.int("id") ?? 0
        title = c.string("title") ?? ""
        description = c.string("description")
        image = c.string("image")
        type = c.int("type") ?? 0
        action = c.string("action")
    }

    /// For type 1 banners `action` is the release id.
    var releaseId: Int? { type == 1 ? action.flatMap(Int.init) : nil }
    var imageURL: URL? { image.flatMap(URL.init(string:)) }
}

struct InterestingResponse: Decodable {
    let content: [InterestingItem]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        content = c.array("content")
    }
}

struct ScheduleResponse: Decodable {
    let days: [(name: String, releases: [Release])]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        let keys: [(String, String)] = [
            ("monday", "Понедельник"), ("tuesday", "Вторник"), ("wednesday", "Среда"),
            ("thursday", "Четверг"), ("friday", "Пятница"), ("saturday", "Суббота"), ("sunday", "Воскресенье")
        ]
        days = keys.map { key, title in (title, c.array(key) as [Release]) }
    }
}

// MARK: - Episodes

struct VoiceoverType: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let icon: String?
    let isSub: Bool
    let episodesCount: Int?
    let viewCount: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        guard let id = c.int("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "type without id"))
        }
        self.id = id
        name = c.string("name") ?? "Озвучка"
        icon = c.string("icon")
        isSub = c.value("is_sub") ?? false
        episodesCount = c.int("episodes_count")
        viewCount = c.int("view_count")
    }
}

struct TypesResponse: Decodable {
    let types: [VoiceoverType]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        types = c.array("types")
    }
}

struct EpisodeSource: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let episodesCount: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        guard let id = c.int("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "source without id"))
        }
        self.id = id
        name = c.string("name") ?? "Плеер"
        episodesCount = c.int("episodes_count")
    }
}

struct SourcesResponse: Decodable {
    let sources: [EpisodeSource]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        sources = c.array("sources")
    }
}

struct Episode: Decodable, Identifiable, Hashable {
    let position: Int
    let releaseId: Int
    let sourceId: Int
    let name: String
    let url: String
    let isFiller: Bool
    let isWatched: Bool
    /// `false` means the API expects the client to resolve and play the stream natively.
    let isIframe: Bool

    var id: Int { position }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        guard let url = c.string("url") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "episode without url"))
        }
        self.url = url
        position = c.int("position") ?? 0
        releaseId = c.int("releaseId") ?? 0
        sourceId = c.int("sourceId") ?? 0
        name = c.string("name") ?? "\(position) серия"
        isFiller = c.value("is_filler") ?? false
        isWatched = c.value("is_watched") ?? false
        isIframe = c.value("iframe") ?? true
    }

    /// AniLibria episodes expose plain HLS playlists, so they play in the native AVPlayer.
    var isLibria: Bool {
        guard let host = playerURL?.host?.lowercased() else { return false }
        return (host.contains("libria") || host.contains("liberty")) && url.contains("iframe.php")
    }

    var playerURL: URL? {
        var s = url
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }
}

struct EpisodesResponse: Decodable {
    let episodes: [Episode]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        episodes = c.array("episodes")
    }
}

// MARK: - Auth / profile

struct Profile: Decodable, Hashable {
    let id: Int
    let login: String
    let avatar: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        id = c.int("id") ?? 0
        login = c.string("login") ?? "Профиль"
        avatar = c.string("avatar")
    }
}

struct SignInResponse: Decodable {
    let code: Int
    let profile: Profile?
    let token: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        code = c.int("code") ?? -1
        profile = c.value("profile")
        if let tokenObj = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: DynamicKey("profileToken")) {
            token = tokenObj.string("token")
        } else {
            token = nil
        }
    }
}

struct CodeResponse: Decodable {
    let code: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        code = c.int("code") ?? -1
    }
}

/// Bookmark lists used by Anixart (`profile_list_status`).
enum WatchList: Int, CaseIterable, Identifiable {
    case watching = 1, plan = 2, completed = 3, holdOn = 4, dropped = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .watching: return "Смотрю"
        case .plan: return "В планах"
        case .completed: return "Просмотрено"
        case .holdOn: return "Отложено"
        case .dropped: return "Брошено"
        }
    }

    var icon: String {
        switch self {
        case .watching: return "play.circle"
        case .plan: return "calendar"
        case .completed: return "checkmark.circle"
        case .holdOn: return "pause.circle"
        case .dropped: return "xmark.circle"
        }
    }
}
