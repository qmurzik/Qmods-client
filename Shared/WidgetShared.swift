import Foundation

/// Data the app hands to its widgets through the shared App Group container.
enum WidgetShared {
    static let group = "group.ru.qmods.anixq"

    struct ContinueItem: Codable, Hashable {
        let title: String
        let slug: String
        let episode: String
        let team: String
        let progress: Double
        let cover: String?
    }

    struct Payload: Codable {
        var continueItems: [ContinueItem]
        var watchingShikiIds: [Int]
        var updated: Date
    }

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget.json")
    }

    static func write(_ payload: Payload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> Payload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func titleURL(_ slug: String) -> URL? { URL(string: "anixq://title/\(slug)") }
}
