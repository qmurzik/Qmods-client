import WidgetKit
import SwiftUI
import ActivityKit

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
        WidgetShared.writeStatus(kind: "continue", note: item == nil ? "нет данных от приложения" : "ok: \(item!.title)")
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
    let slug: String?
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let items: [AiringItem]
    var failed = false
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), items: [AiringItem(title: "Онгоинг", episode: 5, time: Date(), mine: true, slug: nil)])
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
            WidgetShared.writeStatus(kind: "upcoming", note: "нет сети / Shikimori недоступен")
            return TodayEntry(date: Date(), items: [], failed: true)
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Shikimori lists only the *next* episode of each show, so "today" empties out during the day:
        // show everything airing in the next 36 hours instead.
        let now = Date()
        let horizon = now.addingTimeInterval(36 * 3600)
        let items: [AiringItem] = list.compactMap { x in
            guard let a = x["anime"] as? [String: Any], let id = a["id"] as? Int,
                  let s = x["next_episode_at"] as? String,
                  let at = f.date(from: s) ?? ISO8601DateFormatter().date(from: s),
                  at > now.addingTimeInterval(-3600), at < horizon else { return nil }
            let name = (a["russian"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a["name"] as? String ?? "")
            return AiringItem(title: name, episode: x["next_episode"] as? Int ?? 0, time: at, mine: mine.contains(id),
                              slug: nil)
        }
        .sorted { ($0.mine ? 0 : 1, $0.time) < ($1.mine ? 0 : 1, $1.time) }
        WidgetShared.writeStatus(kind: "upcoming", note: "ok: \(items.count) серий, моих \(items.filter(\.mine).count)")
        return TodayEntry(date: Date(), items: items)
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 9 : 4 }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "" }
        if cal.isDateInTomorrow(d) { return "завтра " }
        return d.formatted(.dateTime.day().month(.abbreviated)) + " "
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Скоро выходит").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                Spacer()
                Text("\(entry.items.count)").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            if entry.items.isEmpty {
                Spacer()
                Text(entry.failed ? "Нет связи с Shikimori" : "В ближайшие сутки ничего не выходит")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
            } else {
                ForEach(entry.items.prefix(limit), id: \.self) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.mine ? accent : .white.opacity(0.25)).frame(width: 6, height: 6)
                        Text(item.title).font(.system(size: 12, weight: item.mine ? .semibold : .regular))
                            .lineLimit(1).foregroundStyle(.white)
                        Spacer(minLength: 4)
                        Text(dayLabel(item.time) + item.time.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11).monospacedDigit())
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
        .configurationDisplayName("Скоро выходит")
        .description("Серии, которые выходят в ближайшие сутки, ваши тайтлы — первыми.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct AnixQWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget()
        TodayWidget()
        DownloadLiveActivity()
    }
}

// MARK: - Downloads Live Activity

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    ProgressView(value: context.state.progress).tint(accent)
                }
                Text("\(Int(context.state.progress * 100))%").font(.headline.monospacedDigit())
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent).font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%").font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(context.state.detail).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: context.state.progress).tint(accent)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%").font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
            }
        }
    }
}
