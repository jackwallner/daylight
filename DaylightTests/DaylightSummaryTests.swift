import XCTest
@testable import Daylight

/// The join between "minutes Health recorded" and "daylight the sun has left".
/// The deadline is the product, so most of these are about it being honest at
/// the edges: already met, already impossible, and the polar cases.
final class DaylightSummaryTests: XCTestCase {

    private let seattle = (latitude: 47.6062, longitude: -122.3321)

    private func date(_ value: String, _ zone: String = "America/Los_Angeles") -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: zone)!
        return formatter.date(from: value)!
    }

    private func calendar(_ identifier: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func solarDay(_ value: String, zone: String = "America/Los_Angeles") -> SolarCalculator.Day {
        SolarCalculator.day(
            for: date(value, zone),
            latitude: seattle.latitude,
            longitude: seattle.longitude,
            calendar: calendar(zone)
        )
    }

    // MARK: - The deadline

    func testLatestStartIsTheShortfallBeforeSunset() {
        let now = date("2026-06-21 14:00")
        let solar = solarDay("2026-06-21 12:00")
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 5,
            goalMinutes: 20,
            solar: solar,
            now: now
        )
        let sunset = try! XCTUnwrap(solar.sunset)
        let latestStart = try! XCTUnwrap(snapshot.latestStart)
        XCTAssertEqual(snapshot.minutesToGoal, 15)
        XCTAssertEqual(latestStart, sunset.addingTimeInterval(-15 * 60), accuracy: 1)
    }

    func testNoDeadlineOnceTheGoalIsMet() {
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 25,
            goalMinutes: 20,
            solar: solarDay("2026-06-21 12:00"),
            now: date("2026-06-21 14:00")
        )
        XCTAssertTrue(snapshot.metGoal)
        XCTAssertNil(snapshot.latestStart)
        XCTAssertEqual(snapshot.minutesToGoal, 0)
        XCTAssertEqual(snapshot.goalProgress, 1)
    }

    /// Past the deadline the app must say so rather than show a time that has
    /// already gone by.
    func testDeadlineDisappearsOnceItHasPassed() {
        let solar = solarDay("2026-12-21 12:00")
        let sunset = try! XCTUnwrap(solar.sunset)
        // Ten minutes before sunset, still 60 minutes short.
        let now = sunset.addingTimeInterval(-10 * 60)
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 0,
            goalMinutes: 60,
            solar: solar,
            now: now
        )
        XCTAssertFalse(snapshot.isGoalStillPossible)
        XCTAssertNil(snapshot.latestStart)
        XCTAssertEqual(snapshot.remainingMinutes, 10, accuracy: 0.5)
    }

    func testGoalIsStillPossibleWhenTheShortfallExactlyFits() {
        let solar = solarDay("2026-06-21 12:00")
        let sunset = try! XCTUnwrap(solar.sunset)
        let now = sunset.addingTimeInterval(-30 * 60)
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 0,
            goalMinutes: 30,
            solar: solar,
            now: now
        )
        XCTAssertTrue(snapshot.isGoalStillPossible)
        let latestStart = try! XCTUnwrap(snapshot.latestStart)
        XCTAssertEqual(latestStart, now, accuracy: 1)
    }

    func testBeforeSunriseTheWholeDayIsStillAvailable() {
        let solar = solarDay("2026-06-21 12:00")
        let sunrise = try! XCTUnwrap(solar.sunrise)
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 0,
            goalMinutes: 20,
            solar: solar,
            now: sunrise.addingTimeInterval(-2 * 3600)
        )
        XCTAssertEqual(snapshot.remainingMinutes, solar.length / 60, accuracy: 0.5)
        XCTAssertTrue(snapshot.isGoalStillPossible)
    }

    func testPolarNightHasNoDeadlineAndNoRemainingDaylight() {
        let zone = "Europe/Oslo"
        let tromso = SolarCalculator.day(
            for: date("2026-12-21 12:00", zone),
            latitude: 69.6492,
            longitude: 18.9553,
            calendar: calendar(zone)
        )
        XCTAssertEqual(tromso.condition, .polarNight)
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 0,
            goalMinutes: 20,
            solar: tromso,
            now: date("2026-12-21 12:00", zone)
        )
        XCTAssertEqual(snapshot.remainingMinutes, 0)
        XCTAssertNil(snapshot.latestStart)
        XCTAssertFalse(snapshot.isGoalStillPossible)
    }

    func testPolarDayLeavesTheRestOfTheDayAvailable() {
        let zone = "Europe/Oslo"
        let now = date("2026-06-21 18:00", zone)
        let tromso = SolarCalculator.day(
            for: now,
            latitude: 69.6492,
            longitude: 18.9553,
            calendar: calendar(zone)
        )
        XCTAssertEqual(tromso.condition, .polarDay)
        let snapshot = DaylightSummary.snapshot(
            minutesToday: 0,
            goalMinutes: 20,
            solar: tromso,
            now: now
        )
        // Six hours to midnight.
        XCTAssertEqual(snapshot.remainingMinutes, 360, accuracy: 1)
        XCTAssertTrue(snapshot.isGoalStillPossible)
        XCTAssertNotNil(snapshot.latestStart)
    }

    // MARK: - Totals and sources

    func testTotalMinutesSumsEverySample() {
        let samples = [
            sample(minutes: 12, bundleID: "com.apple.health"),
            sample(minutes: 8, bundleID: "com.apple.health"),
        ]
        XCTAssertEqual(DaylightSummary.totalMinutes(samples), 20)
    }

    func testExcludedSourceDoesNotContribute() {
        let samples = [
            sample(minutes: 12, bundleID: "com.apple.health"),
            sample(minutes: 30, bundleID: "com.other.app"),
        ]
        let total = DaylightSummary.totalMinutes(
            samples,
            excludingSourceBundleIDs: ["com.other.app"]
        )
        XCTAssertEqual(total, 12)
    }

    func testCollapsedWatchSourceExclusionAppliesToEveryBundleVariant() {
        let samples = [
            sample(minutes: 12, bundleID: "com.example.recorder"),
            sample(minutes: 8, bundleID: "com.example.recorder.watch"),
            sample(minutes: 5, bundleID: "com.apple.health"),
        ]

        let total = DaylightSummary.totalMinutes(
            samples,
            excludingSourceBundleIDs: ["com.example.recorder"]
        )

        XCTAssertEqual(total, 5)
    }

    func testNegativeMinutesAreIgnoredRatherThanSubtracted() {
        let samples = [
            sample(minutes: 12, bundleID: "com.apple.health"),
            sample(minutes: -5, bundleID: "com.apple.health"),
        ]
        XCTAssertEqual(DaylightSummary.totalMinutes(samples), 12)
    }

    /// A phone and a watch from one app are one source, not two.
    func testPhoneAndWatchCollapseIntoOneSource() {
        let samples = [
            sample(minutes: 10, bundleID: "com.apple.health", name: "Apple Watch"),
            sample(minutes: 5, bundleID: "com.apple.health.watch", name: "Apple Watch"),
        ]
        let sources = DaylightSummary.sources(samples)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.minutes, 15)
        XCTAssertEqual(sources.first?.bundleID, "com.apple.health")
    }

    func testAppBundleIDStripsKnownSuffixes() {
        XCTAssertEqual(DaylightSummary.appBundleID(for: "com.x.app.watch"), "com.x.app")
        XCTAssertEqual(DaylightSummary.appBundleID(for: "com.x.app.widget"), "com.x.app")
        XCTAssertEqual(DaylightSummary.appBundleID(for: "com.x.app.watchkitapp"), "com.x.app")
        XCTAssertEqual(DaylightSummary.appBundleID(for: "com.x.app"), "com.x.app")
    }

    // MARK: - History

    func testDailyTotalsIncludeEmptyDaysAsZero() {
        let now = date("2026-06-21 20:00")
        let totals = DaylightSummary.dailyTotals(
            [sample(minutes: 30, bundleID: "com.apple.health", start: now.addingTimeInterval(-3600))],
            days: 3,
            goalMinutes: 20,
            latitude: seattle.latitude,
            longitude: seattle.longitude,
            now: now
        )
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals[0].minutes, 30)
        XCTAssertEqual(totals[1].minutes, 0)
        XCTAssertEqual(totals[2].minutes, 0)
        // Every day carries the daylight it actually offered.
        XCTAssertTrue(totals.allSatisfy { $0.availableMinutes > 0 })
    }

    func testDailyTotalsApplyCollapsedWatchSourceExclusion() {
        let now = date("2026-06-21 20:00")
        let totals = DaylightSummary.dailyTotals(
            [
                sample(minutes: 30, bundleID: "com.example.recorder.watch", start: now),
                sample(minutes: 10, bundleID: "com.apple.health", start: now),
            ],
            days: 1,
            goalMinutes: 20,
            latitude: seattle.latitude,
            longitude: seattle.longitude,
            now: now,
            excludingSourceBundleIDs: ["com.example.recorder"]
        )

        XCTAssertEqual(totals.first?.minutes, 10)
    }

    func testShareOfAvailableIsNilWhenThereWasNoDaylight() {
        let total = DaylightSummary.DailyTotal(
            dayKey: "2026-12-21",
            date: date("2026-12-21 12:00"),
            minutes: 0,
            availableMinutes: 0,
            goalMinutes: 20
        )
        XCTAssertNil(total.shareOfAvailable)
    }

    func testAverageAndDaysMetGoal() {
        let totals = [
            total(minutes: 30, goal: 20, daysAgo: 0),
            total(minutes: 10, goal: 20, daysAgo: 1),
            total(minutes: 20, goal: 20, daysAgo: 2),
        ]
        XCTAssertEqual(DaylightSummary.average(totals), 20, accuracy: 0.01)
        XCTAssertEqual(DaylightSummary.daysMetGoal(totals), 2)
    }

    func testHistoricalGoalsDoNotChangeWithTheCurrentTarget() {
        let totals = [
            total(minutes: 25, goal: 60, daysAgo: 0),
            total(minutes: 25, goal: 60, daysAgo: 1),
        ]
        let priorDayKey = totals[1].dayKey

        let updated = DaylightSummary.applyingHistoricalGoals(
            totals,
            goalsByDay: [priorDayKey: 20]
        )

        XCTAssertFalse(updated[0].metGoal)
        XCTAssertTrue(updated[1].metGoal)
        XCTAssertEqual(updated[1].goalMinutes, 20)
    }

    func testAverageOfNothingIsZeroRatherThanACrash() {
        XCTAssertEqual(DaylightSummary.average([]), 0)
    }

    /// An unfinished today must not break a streak that is still live.
    func testTodayNotYetMetDoesNotBreakTheStreak() {
        let now = date("2026-06-21 09:00")
        let totals = [
            total(minutes: 2, goal: 20, daysAgo: 0, from: now),
            total(minutes: 40, goal: 20, daysAgo: 1, from: now),
            total(minutes: 25, goal: 20, daysAgo: 2, from: now),
        ]
        XCTAssertEqual(DaylightSummary.currentStreak(totals, now: now), 2)
    }

    func testAMissedDayEndsTheStreak() {
        let now = date("2026-06-21 21:00")
        let totals = [
            total(minutes: 30, goal: 20, daysAgo: 0, from: now),
            total(minutes: 3, goal: 20, daysAgo: 1, from: now),
            total(minutes: 30, goal: 20, daysAgo: 2, from: now),
        ]
        XCTAssertEqual(DaylightSummary.currentStreak(totals, now: now), 1)
    }

    /// The seasonal drift: in late June the days are already shortening.
    func testAvailableDaylightChangeIsNegativeAfterMidsummer() {
        let change = DaylightSummary.availableDaylightChange(
            days: 30,
            latitude: seattle.latitude,
            longitude: seattle.longitude,
            now: date("2026-07-21 12:00")
        )
        XCTAssertLessThan(change, 0)
    }

    func testAvailableDaylightChangeIsPositiveInSpring() {
        let change = DaylightSummary.availableDaylightChange(
            days: 30,
            latitude: seattle.latitude,
            longitude: seattle.longitude,
            now: date("2026-04-15 12:00")
        )
        XCTAssertGreaterThan(change, 0)
    }

    func testPreviousMonthComparisonUsesCalendarMonth() {
        let now = date("2026-03-31 12:00")
        let expectedPast = calendar().date(byAdding: .month, value: -1, to: now)!
        let today = SolarCalculator.day(
            for: now,
            latitude: seattle.latitude,
            longitude: seattle.longitude
        )
        let past = SolarCalculator.day(
            for: expectedPast,
            latitude: seattle.latitude,
            longitude: seattle.longitude
        )

        let change = DaylightSummary.availableDaylightChangeSincePreviousMonth(
            latitude: seattle.latitude,
            longitude: seattle.longitude,
            now: now
        )

        XCTAssertEqual(change, (today.length - past.length) / 60, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func sample(
        minutes: Double,
        bundleID: String,
        name: String = "Apple Watch",
        start: Date = .now
    ) -> DaylightSummary.Sample {
        DaylightSummary.Sample(
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            minutes: minutes,
            sourceBundleID: bundleID,
            sourceName: name
        )
    }

    private func total(
        minutes: Double,
        goal: Double,
        daysAgo: Int,
        from now: Date = .now
    ) -> DaylightSummary.DailyTotal {
        let day = calendar().date(
            byAdding: .day,
            value: -daysAgo,
            to: calendar().startOfDay(for: now)
        )!
        return DaylightSummary.DailyTotal(
            dayKey: DateHelpers.dayKey(for: day),
            date: day,
            minutes: minutes,
            availableMinutes: 600,
            goalMinutes: goal
        )
    }
}

private func XCTAssertEqual(
    _ lhs: Date,
    _ rhs: Date,
    accuracy: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        lhs.timeIntervalSince1970,
        rhs.timeIntervalSince1970,
        accuracy: accuracy,
        file: file,
        line: line
    )
}
