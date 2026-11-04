import Foundation

struct StreamQuality: Identifiable, Hashable {
    let label: String      // "1080p"
    let url: URL
    var id: String { label }
    var height: Int { Int(label.filter(\.isNumber)) ?? 0 }
}

struct LibriaStream {
    let qualities: [StreamQuality]   // best first
    let skipOpening: ClosedRange<Double>?
}

/// Reads the playlist config that the AniLibria embed page publishes for its own player
/// (`file:[{"id":"s1","skip":"57-157","file":"[480p]https://…m3u8,[720p]…"}]`).
@MainActor
enum LibriaResolver {
    /// One embed page lists every episode of the release, so it is parsed once and cached:
    /// switching to the next episode then starts instantly. Key: page URL without `ep`.
    private static var cache: [String: (date: Date, episodes: [String: LibriaStream], first: LibriaStream)] = [:]

    enum ResolveError: LocalizedError {
        case notFound
        var errorDescription: String? { "Не удалось получить видео AniLibria для этой серии" }
    }

    static func resolve(_ pageURL: URL) async throws -> LibriaStream {
        var comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let episodeParam = items.first { $0.name == "ep" }?.value
        comps?.queryItems = items.filter { $0.name != "ep" }
        let key = comps?.url?.absoluteString ?? pageURL.absoluteString

        // Stream links are signed and expire, so cached entries are kept for 30 minutes.
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < 30 * 60 {
            return episodeParam.flatMap { hit.episodes[$0] } ?? hit.first
        }
        let parsed = try await fetchAll(pageURL)
        cache[key] = (Date(), parsed.episodes, parsed.first)
        return episodeParam.flatMap { parsed.episodes[$0] } ?? parsed.first
    }

    /// Warms the cache for a release so the player opens without waiting.
    static func prefetch(_ pageURL: URL) {
        Task { _ = try? await resolve(pageURL) }
    }

    private static func fetchAll(_ pageURL: URL) async throws -> (episodes: [String: LibriaStream], first: LibriaStream) {
        var req = URLRequest(url: pageURL)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { throw ResolveError.notFound }

        // {"id":"s1","skip":"57-157" | null,"file":"..."}
        let entryPattern = #"\{"id":"s?([^"]*)","skip":(?:null|"([^"]*)"),"file":"([^"]+)""#
        let entryRegex = try NSRegularExpression(pattern: entryPattern)
        let ns = html as NSString
        let matches = entryRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { throw ResolveError.notFound }

        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        var episodes: [String: LibriaStream] = [:]
        var first: LibriaStream?
        for m in matches {
            guard let id = group(m, 1), let rawFile = group(m, 3),
                  let stream = parseStream(file: rawFile, skip: group(m, 2)) else { continue }
            episodes[id] = stream
            if first == nil { first = stream }
        }
        guard let first else { throw ResolveError.notFound }
        return (episodes, first)
    }

    private static func parseStream(file rawFile: String, skip skipRaw: String?) -> LibriaStream? {
        let file = rawFile.replacingOccurrences(of: "\\/", with: "/")
        guard let qualityRegex = try? NSRegularExpression(pattern: #"\[(\d+p)\](https?://[^,\[]+)"#) else { return nil }
        let fns = file as NSString
        var qualities: [StreamQuality] = []
        for m in qualityRegex.matches(in: file, range: NSRange(location: 0, length: fns.length)) {
            let label = fns.substring(with: m.range(at: 1))
            let link = fns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if let url = URL(string: link) { qualities.append(StreamQuality(label: label, url: url)) }
        }
        if qualities.isEmpty, let url = URL(string: file), file.contains(".m3u8") {
            qualities = [StreamQuality(label: "auto", url: url)]
        }
        guard !qualities.isEmpty else { return nil }
        qualities.sort { $0.height > $1.height }

        var skip: ClosedRange<Double>?
        if let s = skipRaw {
            let parts = s.split(separator: "-").compactMap { Double($0) }
            if parts.count == 2, parts[0] < parts[1] { skip = parts[0]...parts[1] }
        }
        return LibriaStream(qualities: qualities, skipOpening: skip)
    }
}
