import Foundation

/// Joins the daylight minutes Apple Health recorded with the daylight the sun
/// still has to offer.
///
/// This is the whole product in one file: every other app in this category
/// reports the first number. The second number is what makes the first one
/// actionable, because "22 minutes" means something different at noon than it
/// does twenty minutes before sunset.
///
/// Pure Swift on purpose. No HealthKit, no CoreLocation, no SwiftUI, so the
/// widgets compile it and the tests run it with no device and no permissions.
enum DaylightSummary {

    /// One Apple Health `timeInDaylight` sample, flattened.
    struct Sample: Equatable {
        var start: Date
        var end: Date
        var minutes: Double
        var sourceBundleID: String
        var sourceName: String

        init(
            start: Date,
            end: Date,
            minutes: Double,
            sourceBundleID: String = "",
            sourceName: String = ""
        ) {
            self.start = start
            self.end = end
            self.minutes = minutes
            self.sourceBundleID = sourceBundleID
            self.sourceName = sourceName
        }
    }

    /// A device that has written daylight minutes, collapsed across the phone
    /// and watch bundle IDs of a single app.
    struct Source: Equatable, Identifiable {
        var id: String { bundleID }
        var bundleID: String
        var name: String
        var minutes: Double
        var lastUpdated: Date
    }

    /// One day's total, for history and trends.
    struct DailyTotal: Equatable, Identifiable {
        var id: String { dayKey }
        var dayKey: String
        var date: Date
        var minutes: Double
        /// Daylight that was available that day, from the sun alone.
        var availableMinutes: Double
        var goalMinutes: Double

        var metGoal: Bool { minutes >= goalMinutes }

        /// Share of the day's available daylight actually spent in it. Nil on a
        /// polar night, where the denominator is zero and a percentage would be
        /// a lie rather than a zero.
        var shareOfAvailable: Double? {
            guard availableMinutes > 0 else { return nil }
            return min(1, minutes / availableMinutes)
        }
    }

    /// Everything the Today screen and the complication need about right now.
    struct Snapshot: Equatable {
        var now: Date
        var minutesToday: Double
        var goalMinutes: Double
        var solar: SolarCalculator.Day

        /// Minutes of daylight between now and sunset.
        var remainingMinutes: Double
        /// Minutes still needed to reach the goal. Zero once it is met.
        var minutesToGoal: Double
        /// 0...1, clamped, so a ring can bind to it directly.
        var goalProgress: Double
        /// Whether enough daylight is left today to still reach the goal.
        var isGoalStillPossible: Bool
        /// The last moment someone could start and still reach the goal before
        /// sunset. Nil once the goal is met or has become unreachable.
        var latestStart: Date?
        var metGoal: Bool
        /// Total daylight the day offered, met or not.
        var availableMinutes: Double
    }

    // MARK: - Today

    /// Build the snapshot the app leads with.
    ///
    /// `minutesToday` is what Health recorded. Everything else is derived from
    /// the sun, so this stays correct with no samples at all, which is the
    /// common case for someone without a supporting watch.
    static func snapshot(
        minutesToday: Double,
        goalMinutes: Double,
        solar: SolarCalculator.Day,
        now: Date = .now
    ) -> Snapshot {
        let recorded = max(0, minutesToday)
        let goal = max(0, goalMinutes)
        let remaining = solar.remainingDaylight(after: now) / 60
        let available = solar.length / 60

        let shortfall = max(0, goal - recorded)
        let metGoal = goal > 0 && recorded >= goal
        let progress = goal > 0 ? min(1, recorded / goal) : (recorded > 0 ? 1 : 0)

        // Enough daylight is left if the shortfall fits before sunset. A met
        // goal is trivially still possible.
        let possible = metGoal || shortfall <= remaining

        var latestStart: Date?
        if !metGoal, possible, shortfall > 0, let deadline = latestStartTime(
            shortfallMinutes: shortfall,
            solar: solar,
            now: now
        ) {
            latestStart = deadline
        }

        return Snapshot(
            now: now,
            minutesToday: recorded,
            goalMinutes: goal,
            solar: solar,
            remainingMinutes: remaining,
            minutesToGoal: shortfall,
            goalProgress: progress,
            isGoalStillPossible: possible,
            latestStart: latestStart,
            metGoal: metGoal,
            availableMinutes: available
        )
    }

    /// The latest someone could step outside and still bank `shortfallMinutes`
    /// before the light goes.
    ///
    /// Anchored on sunset rather than on the clock, so it moves with the season
    /// the way the deadline actually does.
    static func latestStartTime(
        shortfallMinutes: Double,
        solar: SolarCalculator.Day,
        now: Date = .now
    ) -> Date? {
        guard shortfallMinutes > 0 else { return nil }

        let end: Date
        switch solar.condition {
        case .polarNight:
            return nil
        case .polarDay:
            // The sun does not set, so the only limit is the end of the day.
            end = solar.dayCalendar.startOfDay(for: now).addingTimeInterval(24 * 3600)
        case .normal:
            guard let sunset = solar.sunset else { return nil }
            end = sunset
        }

        let deadline = end.addingTimeInterval(-shortfallMinutes * 60)
        // A deadline in the past means the day is already lost; say so with nil
        // rather than showing a time that has been and gone.
        guard deadline >= now else { return nil }
        return deadline
    }

    // MARK: - Sums and sources

    /// Total minutes across `samples`, skipping any source the user switched
    /// off.
    static func totalMinutes(
        _ samples: [Sample],
        excludingSourceBundleIDs excluded: Set<String> = []
    ) -> Double {
        samples
            .filter { !isSourceExcluded($0.sourceBundleID, excluded: excluded) }
            .reduce(0) { $0 + max(0, $1.minutes) }
    }

    /// Source controls use the collapsed app identifier shown in the UI. Match
    /// both that identifier and any legacy raw identifier already in defaults.
    static func isSourceExcluded(_ bundleID: String, excluded: Set<String>) -> Bool {
        excluded.contains(bundleID) || excluded.contains(appBundleID(for: bundleID))
    }

    /// Devices that contributed, newest write first.
    ///
    /// A single app writing from both a phone and a watch shows up once. The
    /// bundle IDs differ by a `.watch` suffix, and two rows for one app reads
    /// as double counting even though the minutes are correct.
    static func sources(_ samples: [Sample]) -> [Source] {
        var byApp: [String: Source] = [:]
        for sample in samples {
            let key = appBundleID(for: sample.sourceBundleID)
            if var existing = byApp[key] {
                existing.minutes += max(0, sample.minutes)
                existing.lastUpdated = max(existing.lastUpdated, sample.end)
                byApp[key] = existing
            } else {
                byApp[key] = Source(
                    bundleID: key,
                    name: sample.sourceName,
                    minutes: max(0, sample.minutes),
                    lastUpdated: sample.end
                )
            }
        }
        return byApp.values.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Collapse a watch bundle ID onto its phone app's.
    static func appBundleID(for bundleID: String) -> String {
        let suffixes = [".watch.widget", ".watchkitapp", ".watchapp", ".watch", ".widget"]
        for suffix in suffixes where bundleID.hasSuffix(suffix) {
            return String(bundleID.dropLast(suffix.count))
        }
        return bundleID
    }

    // MARK: - History

    /// Per-day totals for the last `days` days, most recent first.
    ///
    /// Days with no samples are included with zero. A gap in the chart is
    /// information: it is a day spent indoors, not missing data.
    static func dailyTotals(
        _ samples: [Sample],
        days: Int,
        goalMinutes: Double,
        latitude: Double,
        longitude: Double,
        now: Date = .now,
        excludingSourceBundleIDs excluded: Set<String> = []
    ) -> [DailyTotal] {
        guard days > 0 else { return [] }
        let calendar = SolarCalculator.calendar

        var minutesByDay: [String: Double] = [:]
        for sample in samples where !isSourceExcluded(sample.sourceBundleID, excluded: excluded) {
            let key = DateHelpers.dayKey(for: sample.start)
            minutesByDay[key, default: 0] += max(0, sample.minutes)
        }

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: -offset,
                to: calendar.startOfDay(for: now)
            ) else { return nil }
            let key = DateHelpers.dayKey(for: date)
            let solar = SolarCalculator.day(for: date, latitude: latitude, longitude: longitude)
            return DailyTotal(
                dayKey: key,
                date: date,
                minutes: minutesByDay[key] ?? 0,
                availableMinutes: solar.length / 60,
                goalMinutes: goalMinutes
            )
        }
    }

    /// Mean minutes per day across `totals`. Zero for an empty range.
    static func average(_ totals: [DailyTotal]) -> Double {
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0) { $0 + $1.minutes } / Double(totals.count)
    }

    /// How many of `totals` met their goal.
    static func daysMetGoal(_ totals: [DailyTotal]) -> Int {
        totals.filter(\.metGoal).count
    }

    /// Keep the target that applied when a day was cached. A target changed
    /// today must not recolor previous days or rewrite past streaks.
    static func applyingHistoricalGoals(
        _ totals: [DailyTotal],
        goalsByDay: [String: Double]
    ) -> [DailyTotal] {
        totals.map { total in
            guard let historicalGoal = goalsByDay[total.dayKey], historicalGoal > 0 else {
                return total
            }
            var updated = total
            updated.goalMinutes = historicalGoal
            return updated
        }
    }

    /// Consecutive days meeting the goal, counting back from the most recent.
    ///
    /// `totals` is expected most-recent-first, as `dailyTotals` returns it.
    /// Today is skipped when it has not met the goal yet, so an unfinished day
    /// cannot break a streak that is still live.
    static func currentStreak(_ totals: [DailyTotal], now: Date = .now) -> Int {
        var streak = 0
        for (index, total) in totals.enumerated() {
            if index == 0, !total.metGoal, DateHelpers.isSameDay(total.date, now) {
                continue
            }
            guard total.metGoal else { break }
            streak += 1
        }
        return streak
    }

    /// The seasonal drift: available daylight now against `days` ago.
    ///
    /// Positive means the days are getting longer. This is the number people
    /// actually feel in February and September, and no amount of logging
    /// reveals it, because it comes from the sun rather than from behaviour.
    static func availableDaylightChange(
        days: Int,
        latitude: Double,
        longitude: Double,
        now: Date = .now
    ) -> Double {
        let calendar = SolarCalculator.calendar
        let today = SolarCalculator.day(for: now, latitude: latitude, longitude: longitude)
        guard let past = calendar.date(byAdding: .day, value: -days, to: now) else { return 0 }
        let earlier = SolarCalculator.day(for: past, latitude: latitude, longitude: longitude)
        return (today.length - earlier.length) / 60
    }

    /// Seasonal change against the same calendar day in the prior month.
    static func availableDaylightChangeSincePreviousMonth(
        latitude: Double,
        longitude: Double,
        now: Date = .now
    ) -> Double {
        let calendar = SolarCalculator.calendar
        let today = SolarCalculator.day(for: now, latitude: latitude, longitude: longitude)
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return 0 }
        let earlier = SolarCalculator.day(
            for: previousMonth,
            latitude: latitude,
            longitude: longitude
        )
        return (today.length - earlier.length) / 60
    }
}
