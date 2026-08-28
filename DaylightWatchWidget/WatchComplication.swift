import SwiftData
import SwiftUI
import WidgetKit

struct WatchDaylightEntry: TimelineEntry {
    let date: Date
    let snapshot: DaylightSummary.Snapshot

    static func placeholder(at date: Date = .now) -> WatchDaylightEntry {
        let solar = SolarCalculator.day(for: date, latitude: 47.6062, longitude: -122.3321)
        return WatchDaylightEntry(
            date: date,
            snapshot: DaylightSummary.snapshot(
                minutesToday: 12,
                goalMinutes: 20,
                solar: solar,
                now: date
            )
        )
    }
}

struct WatchDaylightProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchDaylightEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchDaylightEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in completion(isPreview ? .placeholder() : load(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchDaylightEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let entries = (0...8).map { load(at: now.addingTimeInterval(Double($0) * 15 * 60)) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 3600))))
        }
    }

    @MainActor
    private func load(at date: Date) -> WatchDaylightEntry {
        let context = DataService.sharedModelContainer.mainContext
        let key = DateHelpers.dayKey(for: date)
        let descriptor = FetchDescriptor<DailyDaylightRecord>(
            predicate: #Predicate { $0.dateString == key }
        )
        let record = try? context.fetch(descriptor).first

        let defaults = UserDefaults(suiteName: daylightAppGroupID) ?? .standard
        let goal = defaults.object(forKey: daylightGoalMinutesKey) as? Double ?? 20
        let location = CachedLocation.current
        let solar = SolarCalculator.day(
            for: date,
            latitude: location.latitude,
            longitude: location.longitude
        )
        return WatchDaylightEntry(
            date: date,
            snapshot: DaylightSummary.snapshot(
                minutesToday: record?.minutes ?? 0,
                goalMinutes: goal,
                solar: solar,
                now: date
            )
        )
    }
}

struct WatchDaylightComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchDaylightEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "sun.max.fill").font(.caption2)
                Text(DaylightFormat.compactMinutes(entry.snapshot.remainingMinutes))
                    .font(.headline.bold())
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.gold)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("DAYLIGHT LEFT").font(.caption2)
                Text(DaylightFormat.minutes(entry.snapshot.remainingMinutes)).font(.headline.bold())
                Text(subtitle).font(.caption).lineLimit(1)
            }
        case .accessoryInline:
            Label(
                "\(DaylightFormat.compactMinutes(entry.snapshot.remainingMinutes)) daylight left",
                systemImage: "sun.max.fill"
            )
        case .accessoryCorner:
            Text(DaylightFormat.compactMinutes(entry.snapshot.remainingMinutes))
                .font(.headline.bold())
                .widgetLabel { Text("daylight left") }
        default:
            Text(DaylightFormat.compactMinutes(entry.snapshot.remainingMinutes))
        }
    }

    private var subtitle: String {
        let snapshot = entry.snapshot
        if snapshot.metGoal { return "Target reached" }
        if let latestStart = snapshot.latestStart {
            return "Out by \(DaylightFormat.time(latestStart))"
        }
        return "\(DaylightFormat.minutes(snapshot.minutesToday)) so far"
    }
}

@main
struct DaylightWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaylightWatchWidget", provider: WatchDaylightProvider()) { entry in
            WatchDaylightComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daylight left")
        .description("Daylight remaining today and the time to head out.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
