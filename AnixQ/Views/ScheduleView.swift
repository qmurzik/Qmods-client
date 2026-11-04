import SwiftUI

struct ScheduleView: View {
    @State private var days: [(name: String, releases: [Release])] = []
    @State private var error: String?
    @State private var isLoading = false
    @State private var selectedDay = ScheduleView.todayIndex

    private static var todayIndex: Int {
        // Calendar weekday: 1 = Sunday ... 7 = Saturday. Schedule starts on Monday.
        (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    }

    private let shortNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dayPicker
                if isLoading && days.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else if selectedDay < days.count {
                    let day = days[selectedDay]
                    HStack {
                        Text(day.name).font(.title3.bold())
                        if selectedDay == Self.todayIndex { Pill(text: "Сегодня", filled: true) }
                        Spacer()
                        Text("\(day.releases.count) тайтлов").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    if day.releases.isEmpty {
                        EmptyStateView(icon: "moon.zzz", text: "В этот день ничего не выходит")
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(day.releases) { release in
                            NavigationLink(value: ReleaseRoute(id: release.id)) {
                                ReleaseRow(release: release, trailing: nextEpisode(release))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Расписание")
        .releaseDestinations()
        .refreshable { await load() }
        .task { if days.isEmpty { await load() } }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedDay = i }
                } label: {
                    VStack(spacing: 4) {
                        Text(shortNames[i]).font(.system(size: 14, weight: .bold))
                        Circle()
                            .fill(i == Self.todayIndex ? Theme.accent : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(i == selectedDay ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nextEpisode(_ r: Release) -> String? {
        guard let released = r.episodesReleased else { return nil }
        if let total = r.episodesTotal, released >= total { return nil }
        return "\(released + 1) эп."
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            days = try await AnixartAPI.shared.schedule().days
        } catch {
            self.error = error.localizedDescription
        }
    }
}
