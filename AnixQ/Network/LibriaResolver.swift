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
enum LibriaResolver {
    enum ResolveError: LocalizedError {
        case notFound
        var errorDescription: String? { "Не удалось получить видео AniLibria для этой серии" }
    }

    static func resolve(_ pageURL: URL) async throws -> LibriaStream {
        var req = URLRequest(url: pageURL)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { throw ResolveError.notFound }

        let episodeParam = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "ep" }?.value

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

        let chosen = matches.first { group($0, 1) == episodeParam } ?? matches[0]
        guard let rawFile = group(chosen, 3) else { throw ResolveError.notFound }
        let file = rawFile.replacingOccurrences(of: "\\/", with: "/")

        let qualityRegex = try NSRegularExpression(pattern: #"\[(\d+p)\](https?://[^,\[]+)"#)
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
        guard !qualities.isEmpty else { throw ResolveError.notFound }
        qualities.sort { $0.height > $1.height }

        var skip: ClosedRange<Double>?
        if let s = group(chosen, 2) {
            let parts = s.split(separator: "-").compactMap { Double($0) }
            if parts.count == 2, parts[0] < parts[1] { skip = parts[0]...parts[1] }
        }
        return LibriaStream(qualities: qualities, skipOpening: skip)
    }
}
