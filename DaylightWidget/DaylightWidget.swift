import SwiftData
import SwiftUI
import WidgetKit

/// What a widget can know without HealthKit: the cached daily total the app
/// wrote, plus the sun, which it can compute itself from the cached
/// coordinates.
struct DaylightEntry: TimelineEntry {
    let date: Date
    let snapshot: DaylightSummary.Snapshot

    static func placeholder(at date: Date = .now) -> DaylightEntry {
        let solar = SolarCalculator.day(for: date, latitude: 47.6062, longitude: -122.3321)
        return DaylightEntry(
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

@MainActor
enum DaylightEntryLoader {
    static func load(at date: Date) -> DaylightEntry {
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
        return DaylightEntry(
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

struct DaylightProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaylightEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DaylightEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in
            completion(isPreview ? .placeholder() : DaylightEntryLoader.load(at: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DaylightEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            // The remaining figure changes every minute even when no new
            // samples arrive, so the timeline carries its own steps rather than
            // waiting for the app to refresh it.
            let entries = (0...8).map {
                DaylightEntryLoader.load(at: now.addingTimeInterval(Double($0) * 15 * 60))
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 3600))))
        }
    }
}

struct DaylightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DaylightEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Label("Daylight left", systemImage: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(DaylightFormat.minutes(entry.snapshot.remainingMinutes))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.amber)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "sun.max.fill").font(.caption2)
                Text(DaylightFormat.compactMinutes(entry.snapshot.remainingMinutes))
                    .font(.headline.bold())
                    .minimumScaleFactor(0.6)
            }
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
        default:
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Daylight left", systemImage: "sun.max.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(DaylightFormat.minutes(entry.snapshot.remainingMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.amber)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DaylightFormat.minutes(entry.snapshot.minutesToday))
                        .font(.title3.bold())
                    Text("in daylight today")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    if let sunset = entry.snapshot.solar.sunset {
                        Text("sunset \(DaylightFormat.time(sunset))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let snapshot = entry.snapshot
        if snapshot.metGoal { return "Target reached" }
        if let latestStart = snapshot.latestStart {
            return "Head out by \(DaylightFormat.time(latestStart))"
        }
        if snapshot.isGoalStillPossible {
            return "\(DaylightFormat.minutes(snapshot.minutesToGoal)) to target"
        }
        return "Target out of reach today"
    }
}

@main
struct DaylightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaylightWidget", provider: DaylightProvider()) { entry in
            DaylightWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daylight left")
        .description("How much daylight is left today, and the time to head out to reach your target.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
