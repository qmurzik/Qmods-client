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
        VStack(spacing: 0) {
            Picker("День", selection: $selectedDay) {
                ForEach(0..<7, id: \.self) { Text(shortNames[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                if isLoading && days.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else if selectedDay < days.count {
                    let day = days[selectedDay]
                    Section(day.name) {
                        if day.releases.isEmpty {
                            Text("В этот день ничего не выходит").foregroundStyle(.secondary)
                        }
                        ForEach(day.releases) { release in
                            NavigationLink(value: ReleaseRoute(id: release.id)) {
                                ReleaseRow(release: release)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Расписание")
        .releaseDestinations()
        .refreshable { await load() }
        .task { if days.isEmpty { await load() } }
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
