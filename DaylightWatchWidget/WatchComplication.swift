import SwiftData
import SwiftUI
import WidgetKit

struct WatchDaylightEntry: TimelineEntry {
    let date: Date
    let snapshot: DaylightSummary.Snapshot
    let hasRecordedData: Bool
    let isUsingFallbackLocation: Bool

    static func placeholder(at date: Date = .now) -> WatchDaylightEntry {
        let solar = SolarCalculator.day(for: date, latitude: 47.6062, longitude: -122.3321)
        return WatchDaylightEntry(
            date: date,
            snapshot: DaylightSummary.snapshot(
                minutesToday: 12,
                goalMinutes: 20,
                solar: solar,
                now: date
            ),
            hasRecordedData: true,
            isUsingFallbackLocation: false
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
            ),
            hasRecordedData: (defaults.object(forKey: daylightHasRecordedSampleKey) as? Bool) ?? (record != nil),
            isUsingFallbackLocation: !location.isReal
        )
    }
}

struct WatchDaylightComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchDaylightEntry

    /// Every family leads with the recorded total against the target. A
    /// complication is glanced at, and a figure climbing toward a goal is worth
    /// glancing at; the daylight remaining only counts down to zero and then
    /// says nothing until tomorrow. The deadline rides along wherever there is
    /// room for a second line.
    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.snapshot.goalProgress) {
                Image(systemName: "sun.max.fill")
            } currentValueLabel: {
                Text(entry.hasRecordedData ? DaylightFormat.compactMinutes(entry.snapshot.minutesToday) : "·")
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(entry.snapshot.metGoal ? Theme.mint : Theme.gold)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.hasRecordedData ? "IN DAYLIGHT" : "NO SAMPLE").font(.caption2)
                Text(entry.hasRecordedData
                     ? "\(DaylightFormat.minutes(entry.snapshot.minutesToday)) of \(DaylightFormat.minutes(entry.snapshot.goalMinutes))"
                     : "Apple Watch data pending")
                    .font(.headline.bold())
                Text(subtitle).font(.caption).lineLimit(1)
            }
        case .accessoryInline:
            Label(
                entry.hasRecordedData
                    ? "\(DaylightFormat.compactMinutes(entry.snapshot.minutesToday)) of \(DaylightFormat.compactMinutes(entry.snapshot.goalMinutes)) outside"
                    : "No daylight sample today",
                systemImage: "sun.max.fill"
            )
        case .accessoryCorner:
            Text(entry.hasRecordedData ? DaylightFormat.compactMinutes(entry.snapshot.minutesToday) : "·")
                .font(.headline.bold())
                .widgetLabel {
                    Gauge(value: entry.snapshot.goalProgress) { Text("in daylight") }
                        .tint(entry.snapshot.metGoal ? Theme.mint : Theme.gold)
                }
        default:
            Text(DaylightFormat.compactMinutes(entry.snapshot.minutesToday))
        }
    }

    private var subtitle: String {
        if !entry.hasRecordedData { return "No sample today" }
        if entry.isUsingFallbackLocation { return "Open app for sunset" }
        let snapshot = entry.snapshot
        if snapshot.metGoal { return "Target reached" }
        if let latestStart = snapshot.latestStart {
            return "Out by \(DaylightFormat.time(latestStart))"
        }
        return "\(DaylightFormat.minutes(snapshot.remainingMinutes)) of light left"
    }
}

@main
struct DaylightWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaylightWatchWidget", provider: WatchDaylightProvider()) { entry in
            WatchDaylightComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Minutes in daylight")
        .description("Your minutes outside against today's target, and the time to head out.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
