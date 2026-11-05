import Foundation
import UIKit
import Vision

/// Short-video screenshots (TikTok/Shorts) crop and mirror the frame, so trace.moe often can't match
/// them — but their caption or hashtags usually name the anime. This reads the text on the screenshot
/// and searches AnimeLib with it.
enum TextHints {
    /// UI words of popular apps that never name an anime.
    private static let noise: Set<String> = [
        "подписки", "рекомендации", "главная", "профиль", "входящие", "друзья", "сообщество", "live", "для",
        "вас", "following", "for", "you", "home", "inbox", "profile", "shorts", "подписаться", "anime", "аниме",
        "animeshorts", "anime shorts", "назад", "ч", "мин", "дн", "kz", "ru", "lte", "rec", "rek", "edit",
        "animeedit", "аниме момент", "анимемомент", "анимешник", "отметки", "нравится", "комментарии",
        "поделиться", "звук", "оригинальный", "original", "sound", "реклама", "ещё", "еще"
    ]

    static func recognize(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines)
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["ru-RU", "en-US", "ja-JP"]
            req.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cg).perform([req])
            } catch {
                cont.resume(returning: [])
            }
        }
    }

    /// Phrases worth searching: caption fragments and hashtags, minus UI words, times and counters.
    static func queries(from lines: [String]) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
            guard t.count >= 3, !noise.contains(t.lowercased()),
                  t.rangeOfCharacter(from: .letters) != nil,
                  !t.contains(":"), Double(t.replacingOccurrences(of: ",", with: ".")) == nil,
                  !out.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
            out.append(t)
        }
        for line in lines {
            // Hashtags separately (#аляиногдакокетничает), the rest as a phrase.
            let words = line.split(separator: " ").map(String.init)
            for w in words where w.hasPrefix("#") { add(String(w.dropFirst())) }
            let phrase = words.filter { !$0.hasPrefix("#") && !$0.hasPrefix("@") }.joined(separator: " ")
            add(phrase)
            // Single capitalised words are often character names ("Аля", "Фрирен").
            for w in phrase.split(separator: " ") where w.count >= 3 && (w.first?.isUppercase ?? false) {
                add(String(w))
            }
        }
        return Array(out.prefix(8))
    }

    /// Titles for the recognised phrases: searched on Shikimori (good with partial names like "Аля"),
    /// ranked by how many phrases hit them, then matched to AnimeLib by Shikimori id.
    static func search(_ queries: [String]) async -> [Title] {
        var score: [Int: (names: [String], score: Int)] = [:]
        for (i, q) in queries.prefix(6).enumerated() {
            // A single capitalised word is usually a character name — a strong hint.
            let nameBonus = (!q.contains(" ") && (q.first?.isUppercase ?? false)) ? 8 : 0
            for (rank, hit) in await ShikiAPI.search(q, limit: 3).enumerated() {
                let weight = (6 - i) * 2 + (3 - rank) * 3 + nameBonus
                score[hit.id] = ([hit.name, hit.russian], (score[hit.id]?.score ?? 0) + weight)
            }
        }
        let ranked = score.sorted { $0.value.score > $1.value.score }.prefix(6)
        var titles: [Title] = []
        for (sid, v) in ranked {
            if let t = await LibAPI.title(shikiId: sid, names: v.names), !titles.contains(where: { $0.id == t.id }) {
                titles.append(t)
            }
        }
        DebugLog.log("trace: text queries \(queries) -> \(titles.prefix(3).map(\.title))")
        return titles
    }
}
