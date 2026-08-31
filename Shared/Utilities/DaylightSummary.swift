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
        /// Whether Apple Health returned at least one daylight sample for this
        /// date. The personal model excludes missing days instead of assuming
        /// that an absent Watch record means zero exposure.
        var hasRecordedData: Bool = true

        var metGoal: Bool { minutes >= goalMinutes }

        /// Share of the day's available daylight actually spent in it. Nil on a
        /// polar night, where the denominator is zero and a percentage would be
        /// a lie rather than a zero.
        var shareOfAvailable: Double? {
            guard availableMinutes > 0 else { return nil }
            return min(1, minutes / availableMinutes)
        }
    }

    enum SleepState: Equatable {
        case asleep
        case awake
    }

    /// One Apple Health sleep stage. In-bed samples are excluded because they
    /// overlap the stage records and are not proof that the user was asleep.
    struct SleepSample: Equatable {
        var start: Date
        var end: Date
        var state: SleepState = .asleep
    }

    /// A within-person comparison between nights following the user's higher
    /// and lower recorded daylight days. This is deliberately descriptive. It
    /// does not assign a score or infer that daylight caused the difference.
    struct SleepPattern: Equatable {
        var higherDaylightMinutes: Double
        var lowerDaylightMinutes: Double
        var higherDaylightSleepMinutes: Double
        var lowerDaylightSleepMinutes: Double
        var nightsPerGroup: Int

        var pairedNightCount: Int { nightsPerGroup * 2 }
        var sleepDifferenceMinutes: Double {
            higherDaylightSleepMinutes - lowerDaylightSleepMinutes
        }
    }

    struct SleepNight: Equatable {
        var dayKey: String
        var asleepMinutes: Double
        var awakeMinutes: Double?

        var continuity: Double? {
            guard let awakeMinutes else { return nil }
            let total = asleepMinutes + awakeMinutes
            guard total > 0 else { return nil }
            return asleepMinutes / total
        }
    }

    enum HealthSignal: String, CaseIterable, Equatable, Identifiable {
        case sleepDuration
        case sleepContinuity
        case steps
        case exerciseMinutes
        case activeEnergy
        case restingHeartRate
        case heartRateVariability
        case respiratoryRate

        var id: String { rawValue }
    }

    struct HealthDay: Equatable {
        var dayKey: String
        var daylightMinutes: Double
        var sleepDurationMinutes: Double? = nil
        var sleepContinuity: Double? = nil
        var steps: Double? = nil
        var exerciseMinutes: Double? = nil
        var activeEnergyCalories: Double? = nil
        var restingHeartRate: Double? = nil
        var heartRateVariabilityMilliseconds: Double? = nil
        var respiratoryRate: Double? = nil

        func value(for signal: HealthSignal) -> Double? {
            switch signal {
            case .sleepDuration: sleepDurationMinutes
            case .sleepContinuity: sleepContinuity
            case .steps: steps
            case .exerciseMinutes: exerciseMinutes
            case .activeEnergy: activeEnergyCalories
            case .restingHeartRate: restingHeartRate
            case .heartRateVariability: heartRateVariabilityMilliseconds
            case .respiratoryRate: respiratoryRate
            }
        }
    }

    struct HealthRelationship: Equatable, Identifiable {
        var id: HealthSignal { signal }
        var signal: HealthSignal
        var sampleCount: Int
        var correlation: Double? = nil
        var confidenceLow: Double? = nil
        var confidenceHigh: Double? = nil
        var lowerDaylightAverage: Double? = nil
        var higherDaylightAverage: Double? = nil
        var lowerOutcomeAverage: Double? = nil
        var higherOutcomeAverage: Double? = nil

        var isClear: Bool {
            guard let confidenceLow, let confidenceHigh else { return false }
            return confidenceLow > 0 || confidenceHigh < 0
        }

        var outcomeDifference: Double? {
            guard let lowerOutcomeAverage, let higherOutcomeAverage else { return nil }
            return higherOutcomeAverage - lowerOutcomeAverage
        }
    }

    struct PersonalHealthModel: Equatable {
        var relationships: [HealthRelationship]

        var strongestClearRelationship: HealthRelationship? {
            relationships
                .filter(\.isClear)
                .max { abs($0.correlation ?? 0) < abs($1.correlation ?? 0) }
        }

        var evaluatedCount: Int {
            relationships.filter { $0.correlation != nil }.count
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
    /// Days with no samples stay in the range so the chart can show a gap, but
    /// `hasRecordedData` keeps that gap distinct from a measured zero.
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
            let recordedMinutes = minutesByDay[key]
            return DailyTotal(
                dayKey: key,
                date: date,
                minutes: recordedMinutes ?? 0,
                availableMinutes: solar.length / 60,
                goalMinutes: goalMinutes,
                hasRecordedData: recordedMinutes != nil
            )
        }
    }

    /// Mean minutes across days with a recorded sample. Zero when none exist.
    static func average(_ totals: [DailyTotal]) -> Double {
        let recorded = totals.filter(\.hasRecordedData)
        guard !recorded.isEmpty else { return 0 }
        return recorded.reduce(0) { $0 + $1.minutes } / Double(recorded.count)
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

    // MARK: - Daylight and sleep

    /// Compare recorded sleep following the user's higher- and lower-daylight
    /// days. The middle observation is omitted for an odd sample count so both
    /// groups remain the same size.
    ///
    /// A sleep stage ending before noon is associated with the prior day by
    /// shifting its end back 12 hours. This keeps stages on either side of
    /// midnight in the same night. Overlapping stages and duplicate sources are
    /// merged before duration is calculated.
    static func sleepPattern(
        daylightTotals: [DailyTotal],
        sleepSamples: [SleepSample],
        minimumNightsPerGroup: Int = 3
    ) -> SleepPattern? {
        guard minimumNightsPerGroup > 0 else { return nil }
        let sleepByDay = sleepMinutesByPrecedingDay(sleepSamples)
        let pairs = daylightTotals.compactMap { total -> (daylight: Double, sleep: Double)? in
            guard let sleep = sleepByDay[total.dayKey], sleep > 0 else { return nil }
            return (max(0, total.minutes), sleep)
        }
        .sorted { lhs, rhs in
            if lhs.daylight == rhs.daylight { return lhs.sleep < rhs.sleep }
            return lhs.daylight < rhs.daylight
        }

        let groupSize = pairs.count / 2
        guard groupSize >= minimumNightsPerGroup else { return nil }
        let lower = Array(pairs.prefix(groupSize))
        let higher = Array(pairs.suffix(groupSize))
        let lowerDaylight = mean(lower.map(\.daylight))
        let higherDaylight = mean(higher.map(\.daylight))
        guard higherDaylight - lowerDaylight >= 1 else { return nil }

        return SleepPattern(
            higherDaylightMinutes: higherDaylight,
            lowerDaylightMinutes: lowerDaylight,
            higherDaylightSleepMinutes: mean(higher.map(\.sleep)),
            lowerDaylightSleepMinutes: mean(lower.map(\.sleep)),
            nightsPerGroup: groupSize
        )
    }

    static func sleepMinutesByPrecedingDay(
        _ samples: [SleepSample]
    ) -> [String: Double] {
        sleepNights(samples).mapValues(\.asleepMinutes)
    }

    static func sleepNights(_ samples: [SleepSample]) -> [String: SleepNight] {
        let asleep = intervalMinutesByPrecedingDay(
            samples.filter { $0.state == .asleep }
        )
        let awake = intervalMinutesByPrecedingDay(
            samples.filter { $0.state == .awake }
        )
        let keys = Set(asleep.keys).union(awake.keys)
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            guard let asleepMinutes = asleep[key], asleepMinutes > 0 else { return nil }
            return (
                key,
                SleepNight(
                    dayKey: key,
                    asleepMinutes: asleepMinutes,
                    awakeMinutes: awake[key]
                )
            )
        })
    }

    private static func intervalMinutesByPrecedingDay(
        _ samples: [SleepSample]
    ) -> [String: Double] {
        var intervalsByDay: [String: [(start: Date, end: Date)]] = [:]
        for sample in samples where sample.end > sample.start {
            let keyDate = sample.end.addingTimeInterval(-12 * 3600)
            let key = DateHelpers.dayKey(for: keyDate)
            intervalsByDay[key, default: []].append((sample.start, sample.end))
        }

        return intervalsByDay.mapValues { intervals in
            let sorted = intervals.sorted { $0.start < $1.start }
            guard var current = sorted.first else { return 0 }
            var duration: TimeInterval = 0
            for interval in sorted.dropFirst() {
                if interval.start <= current.end {
                    current.end = max(current.end, interval.end)
                } else {
                    duration += current.end.timeIntervalSince(current.start)
                    current = interval
                }
            }
            duration += current.end.timeIntervalSince(current.start)
            return duration / 60
        }
    }

    /// Evaluate every signal the app requested. A result is only called clear
    /// when its confidence interval excludes zero after a Bonferroni correction
    /// across all eight checks.
    /// Sparse signals remain in the result so the UI can say they were checked
    /// without pretending there was enough data.
    static func personalHealthModel(
        days: [HealthDay],
        minimumSampleCount: Int = 14
    ) -> PersonalHealthModel {
        let relationships = HealthSignal.allCases.map { signal in
            relationship(
                signal: signal,
                pairs: days.compactMap { day in
                    guard let outcome = day.value(for: signal) else { return nil }
                    return (day.daylightMinutes, outcome)
                },
                minimumSampleCount: minimumSampleCount
            )
        }
        return PersonalHealthModel(relationships: relationships)
    }

    private static func relationship(
        signal: HealthSignal,
        pairs: [(daylight: Double, outcome: Double)],
        minimumSampleCount: Int
    ) -> HealthRelationship {
        let count = pairs.count
        guard count >= max(4, minimumSampleCount),
              let correlation = pearsonCorrelation(pairs)
        else {
            return HealthRelationship(signal: signal, sampleCount: count)
        }

        let sorted = pairs.sorted { $0.daylight < $1.daylight }
        let groupSize = count / 2
        let lower = Array(sorted.prefix(groupSize))
        let higher = Array(sorted.suffix(groupSize))
        let bounded = min(0.999_999, max(-0.999_999, correlation))
        let fisher = 0.5 * log((1 + bounded) / (1 - bounded))
        // Two-sided alpha .05 / 8. This keeps the family-wise false-positive
        // rate at 5% even though the model checks eight Health signals.
        let correctedCriticalValue = 2.734
        let margin = correctedCriticalValue / sqrt(Double(count - 3))
        let low = tanh(fisher - margin)
        let high = tanh(fisher + margin)

        return HealthRelationship(
            signal: signal,
            sampleCount: count,
            correlation: correlation,
            confidenceLow: low,
            confidenceHigh: high,
            lowerDaylightAverage: mean(lower.map(\.daylight)),
            higherDaylightAverage: mean(higher.map(\.daylight)),
            lowerOutcomeAverage: mean(lower.map(\.outcome)),
            higherOutcomeAverage: mean(higher.map(\.outcome))
        )
    }

    private static func pearsonCorrelation(
        _ pairs: [(daylight: Double, outcome: Double)]
    ) -> Double? {
        let daylightMean = mean(pairs.map(\.daylight))
        let outcomeMean = mean(pairs.map(\.outcome))
        var numerator = 0.0
        var daylightSquares = 0.0
        var outcomeSquares = 0.0
        for pair in pairs {
            let daylightDelta = pair.daylight - daylightMean
            let outcomeDelta = pair.outcome - outcomeMean
            numerator += daylightDelta * outcomeDelta
            daylightSquares += daylightDelta * daylightDelta
            outcomeSquares += outcomeDelta * outcomeDelta
        }
        let denominator = sqrt(daylightSquares * outcomeSquares)
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
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
