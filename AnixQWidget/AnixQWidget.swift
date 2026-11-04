import WidgetKit
import SwiftUI

// MARK: - Helpers

private func loadImage(_ string: String?) async -> UIImage? {
    guard let string, let url = URL(string: string) else { return nil }
    var req = URLRequest(url: url)
    req.timeoutInterval = 10
    if url.host?.contains("imglib") == true { req.setValue("https://anilib.me/", forHTTPHeaderField: "Referer") }
    guard let (data, _) = try? await URLSession.shared.data(for: req), let img = UIImage(data: data) else { return nil }
    // Widgets have a tight memory budget: downscale.
    let target = CGSize(width: 300, height: 300 * img.size.height / max(img.size.width, 1))
    return UIGraphicsImageRenderer(size: target).image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
}

private let accent = Color(red: 1.0, green: 0.27, blue: 0.42)

extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

// MARK: - Continue watching

struct ContinueEntry: TimelineEntry {
    let date: Date
    let item: WidgetShared.ContinueItem?
    let image: UIImage?
    let hasAppGroup: Bool
}

struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry {
        ContinueEntry(date: Date(), item: WidgetShared.ContinueItem(title: "Клинок, рассекающий демонов", slug: "",
                                                                    episode: "5", team: "AniLibria", progress: 0.4,
                                                                    cover: nil),
                      image: nil, hasAppGroup: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        Task {
            let e = await entry()
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(3600))))
        }
    }

    private func entry() async -> ContinueEntry {
        let payload = WidgetShared.read()
        let item = payload?.continueItems.first
        return ContinueEntry(date: Date(), item: item, image: await loadImage(item?.cover),
                             hasAppGroup: WidgetShared.fileURL != nil)
    }
}

struct ContinueWidgetView: View {
    let entry: ContinueEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let item = entry.item {
                content(item)
                    .widgetURL(WidgetShared.titleURL(item.slug))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "play.rectangle.on.rectangle").font(.title2).foregroundStyle(accent)
                    Text(entry.hasAppGroup ? "Начните смотреть в AnixQ" : "Откройте AnixQ")
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .widgetBackground(.black)
    }

    @ViewBuilder
    private func content(_ item: WidgetShared.ContinueItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let img = entry.image {
                Image(uiImage: img).resizable().scaledToFill()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("ПРОДОЛЖИТЬ").font(.system(size: 9, weight: .heavy)).foregroundStyle(accent)
                Text(item.title).font(.system(size: family == .systemSmall ? 13 : 16, weight: .bold))
                    .lineLimit(2).foregroundStyle(.white)
                Text("Серия \(item.episode) · \(item.team)").font(.caption2).foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(accent).frame(width: g.size.width * item.progress)
                    }
                }
                .frame(height: 3)
            }
            .padding(12)
        }
    }
}

struct ContinueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnixQContinue", provider: ContinueProvider()) { entry in
            ContinueWidgetView(entry: entry)
        }
        .configurationDisplayName("Продолжить просмотр")
        .description("Последняя серия, которую вы смотрели.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Airing today

struct AiringItem: Hashable {
    let title: String
    let episode: Int
    let time: Date
    let mine: Bool
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let items: [AiringItem]
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), items: [AiringItem(title: "Онгоинг", episode: 5, time: Date(), mine: true)])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let e = await entry()
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(2 * 3600))))
        }
    }

    private func entry() async -> TodayEntry {
        let mine = Set(WidgetShared.read()?.watchingShikiIds ?? [])
        var req = URLRequest(url: URL(string: "https://shikimori.io/api/calendar")!)
        req.setValue("AnixQ", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return TodayEntry(date: Date(), items: [])
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cal = Calendar.current
        let items: [AiringItem] = list.compactMap { x in
            guard let a = x["anime"] as? [String: Any], let id = a["id"] as? Int,
                  let s = x["next_episode_at"] as? String,
                  let at = f.date(from: s) ?? ISO8601DateFormatter().date(from: s),
                  cal.isDateInToday(at) else { return nil }
            let name = (a["russian"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a["name"] as? String ?? "")
            return AiringItem(title: name, episode: x["next_episode"] as? Int ?? 0, time: at, mine: mine.contains(id))
        }
        .sorted { ($0.mine ? 0 : 1, $0.time) < ($1.mine ? 0 : 1, $1.time) }
        return TodayEntry(date: Date(), items: items)
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 9 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Сегодня выходит").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                Spacer()
                Text("\(entry.items.count)").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            if entry.items.isEmpty {
                Spacer()
                Text("Сегодня ничего не выходит").font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
            } else {
                ForEach(entry.items.prefix(limit), id: \.self) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.mine ? accent : .white.opacity(0.25)).frame(width: 6, height: 6)
                        Text(item.title).font(.system(size: 12, weight: item.mine ? .semibold : .regular))
                            .lineLimit(1).foregroundStyle(.white)
                        Spacer(minLength: 4)
                        Text(item.time, style: .time).font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(2)
        .widgetBackground(.black)
        .widgetURL(URL(string: "anixq://schedule"))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnixQToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Сегодня выходит")
        .description("Расписание серий на сегодня, ваши тайтлы — первыми.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct AnixQWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget()
        TodayWidget()
    }
}
