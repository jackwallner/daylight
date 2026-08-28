import XCTest
@testable import Daylight

/// The solar maths is the one part of this app that can be silently wrong: a
/// sunset half an hour out looks completely plausible on screen. These tests
/// pin it against published times for real cities and against the invariants
/// the geometry has to obey everywhere.
final class SolarCalculatorTests: XCTestCase {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func noon(_ day: String, _ zone: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: zone)!
        return formatter.date(from: "\(day) 12:00")!
    }

    private func clock(_ date: Date, _ zone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: zone)!
        return formatter.string(from: date)
    }

    /// Minutes between a computed time and the published one.
    private func drift(_ date: Date?, from expected: String, on day: String, zone: String) -> Double {
        guard let date else { return .infinity }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: zone)!
        let target = formatter.date(from: "\(day) \(expected)")!
        return abs(date.timeIntervalSince(target)) / 60
    }

    // MARK: - Published times

    func testSeattleSummerSolsticeMatchesPublishedTimes() {
        let zone = "America/Los_Angeles"
        let day = SolarCalculator.day(
            for: noon("2026-06-21", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        XCTAssertLessThanOrEqual(drift(day.sunrise, from: "05:11", on: "2026-06-21", zone: zone), 2)
        XCTAssertLessThanOrEqual(drift(day.sunset, from: "21:11", on: "2026-06-21", zone: zone), 2)
    }

    func testSeattleWinterSolsticeMatchesPublishedTimes() {
        let zone = "America/Los_Angeles"
        let day = SolarCalculator.day(
            for: noon("2026-12-21", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        XCTAssertLessThanOrEqual(drift(day.sunrise, from: "07:55", on: "2026-12-21", zone: zone), 2)
        XCTAssertLessThanOrEqual(drift(day.sunset, from: "16:20", on: "2026-12-21", zone: zone), 2)
    }

    func testLondonSummerSolsticeMatchesPublishedTimes() {
        let zone = "Europe/London"
        let day = SolarCalculator.day(
            for: noon("2026-06-21", zone),
            latitude: 51.5074,
            longitude: -0.1278,
            calendar: calendar(zone)
        )
        XCTAssertLessThanOrEqual(drift(day.sunrise, from: "04:43", on: "2026-06-21", zone: zone), 2)
        XCTAssertLessThanOrEqual(drift(day.sunset, from: "21:21", on: "2026-06-21", zone: zone), 2)
    }

    /// Southern hemisphere, and a longitude far from its zone meridian.
    func testSydneySummerSolsticeMatchesPublishedTimes() {
        let zone = "Australia/Sydney"
        let day = SolarCalculator.day(
            for: noon("2026-12-21", zone),
            latitude: -33.8688,
            longitude: 151.2093,
            calendar: calendar(zone)
        )
        XCTAssertLessThanOrEqual(drift(day.sunrise, from: "05:40", on: "2026-12-21", zone: zone), 2)
        XCTAssertLessThanOrEqual(drift(day.sunset, from: "20:05", on: "2026-12-21", zone: zone), 2)
    }

    // MARK: - Invariants

    func testSunriseIsBeforeSolarNoonWhichIsBeforeSunset() {
        let zone = "America/Los_Angeles"
        let day = SolarCalculator.day(
            for: noon("2026-09-15", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let sunrise = try! XCTUnwrap(day.sunrise)
        let sunset = try! XCTUnwrap(day.sunset)
        XCTAssertLessThan(sunrise, day.solarNoon)
        XCTAssertLessThan(day.solarNoon, sunset)
    }

    /// Sunrise and sunset sit either side of solar noon by the same amount.
    func testDayIsSymmetricAboutSolarNoon() {
        let zone = "Europe/Berlin"
        let day = SolarCalculator.day(
            for: noon("2026-04-10", zone),
            latitude: 52.52,
            longitude: 13.405,
            calendar: calendar(zone)
        )
        let sunrise = try! XCTUnwrap(day.sunrise)
        let sunset = try! XCTUnwrap(day.sunset)
        let before = day.solarNoon.timeIntervalSince(sunrise)
        let after = sunset.timeIntervalSince(day.solarNoon)
        XCTAssertEqual(before, after, accuracy: 60)
    }

    func testNorthernSummerDaysAreLongerThanWinterDays() {
        let zone = "America/Los_Angeles"
        let summer = SolarCalculator.day(
            for: noon("2026-06-21", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let winter = SolarCalculator.day(
            for: noon("2026-12-21", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        XCTAssertGreaterThan(summer.length, winter.length)
    }

    /// The equinox is a few minutes over twelve hours, not exactly twelve: the
    /// sun's disc and atmospheric refraction both add light at each end.
    func testEquinoxAtTheEquatorIsJustOverTwelveHours() {
        let zone = "America/Guayaquil"
        let day = SolarCalculator.day(
            for: noon("2026-03-20", zone),
            latitude: 0,
            longitude: -78.4678,
            calendar: calendar(zone)
        )
        let hours = day.length / 3600
        XCTAssertGreaterThan(hours, 12.0)
        XCTAssertLessThan(hours, 12.25)
    }

    func testDeclinationReachesTheTropicsAtTheSolstices() {
        let june = SolarCalculator.declination(on: noon("2026-06-21", "UTC"))
        let december = SolarCalculator.declination(on: noon("2026-12-21", "UTC"))
        XCTAssertEqual(june, 23.44, accuracy: 0.1)
        XCTAssertEqual(december, -23.44, accuracy: 0.1)
    }

    func testEquationOfTimeStaysWithinItsKnownBounds() {
        let zone = "UTC"
        for dayOfYear in stride(from: 1, through: 365, by: 5) {
            var components = DateComponents()
            components.year = 2026
            components.day = dayOfYear
            components.month = 1
            components.hour = 12
            let date = calendar(zone).date(from: components)!
            let value = SolarCalculator.equationOfTime(on: date)
            XCTAssertLessThan(abs(value), 17.5, "day \(dayOfYear) gave \(value)")
        }
    }

    // MARK: - Polar cases

    func testTromsoHasNoSunsetAtMidsummer() {
        let zone = "Europe/Oslo"
        let day = SolarCalculator.day(
            for: noon("2026-06-21", zone),
            latitude: 69.6492,
            longitude: 18.9553,
            calendar: calendar(zone)
        )
        XCTAssertEqual(day.condition, .polarDay)
        XCTAssertNil(day.sunrise)
        XCTAssertNil(day.sunset)
        XCTAssertEqual(day.length, 24 * 3600)
    }

    func testTromsoHasNoSunriseAtMidwinterButKeepsCivilTwilight() {
        let zone = "Europe/Oslo"
        let day = SolarCalculator.day(
            for: noon("2026-12-21", zone),
            latitude: 69.6492,
            longitude: 18.9553,
            calendar: calendar(zone)
        )
        XCTAssertEqual(day.condition, .polarNight)
        XCTAssertNil(day.sunrise)
        XCTAssertEqual(day.length, 0)
        // The sun stays below the horizon but the sky still brightens, which is
        // the difference between "no daylight" and "pitch dark all day".
        XCTAssertNotNil(day.civilDawn)
        XCTAssertNotNil(day.civilDusk)
    }

    func testPolarNightOffersNoRemainingDaylight() {
        let zone = "Europe/Oslo"
        let date = noon("2026-12-21", zone)
        let day = SolarCalculator.day(
            for: date,
            latitude: 69.6492,
            longitude: 18.9553,
            calendar: calendar(zone)
        )
        XCTAssertEqual(day.remainingDaylight(after: date), 0)
        XCTAssertFalse(day.isDaylight(at: date))
    }

    // MARK: - Remaining daylight

    func testRemainingDaylightBeforeSunriseIsTheWholeDay() {
        let zone = "America/Los_Angeles"
        let date = noon("2026-06-21", zone)
        let day = SolarCalculator.day(
            for: date,
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let beforeSunrise = try! XCTUnwrap(day.sunrise).addingTimeInterval(-3600)
        XCTAssertEqual(day.remainingDaylight(after: beforeSunrise), day.length, accuracy: 1)
    }

    func testRemainingDaylightAfterSunsetIsZero() {
        let zone = "America/Los_Angeles"
        let date = noon("2026-06-21", zone)
        let day = SolarCalculator.day(
            for: date,
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let afterSunset = try! XCTUnwrap(day.sunset).addingTimeInterval(600)
        XCTAssertEqual(day.remainingDaylight(after: afterSunset), 0)
    }

    func testRemainingDaylightShrinksAsTheDayGoesOn() {
        let zone = "America/Los_Angeles"
        let date = noon("2026-06-21", zone)
        let day = SolarCalculator.day(
            for: date,
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let sunrise = try! XCTUnwrap(day.sunrise)
        let early = day.remainingDaylight(after: sunrise.addingTimeInterval(3600))
        let later = day.remainingDaylight(after: sunrise.addingTimeInterval(4 * 3600))
        XCTAssertGreaterThan(early, later)
    }

    // MARK: - Elevation

    func testSunIsHighestAroundSolarNoon() {
        let zone = "America/Los_Angeles"
        let day = SolarCalculator.day(
            for: noon("2026-06-21", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let atNoon = SolarCalculator.elevation(
            at: day.solarNoon,
            latitude: 47.6062,
            longitude: -122.3321
        )
        let threeHoursLater = SolarCalculator.elevation(
            at: day.solarNoon.addingTimeInterval(3 * 3600),
            latitude: 47.6062,
            longitude: -122.3321
        )
        XCTAssertGreaterThan(atNoon, threeHoursLater)
        // Seattle at midsummer: 90 - 47.6 + 23.4 ≈ 65.8 degrees.
        XCTAssertEqual(atNoon, 65.8, accuracy: 1.0)
    }

    func testSunIsNearTheHorizonAtSunrise() {
        let zone = "America/Los_Angeles"
        let day = SolarCalculator.day(
            for: noon("2026-09-15", zone),
            latitude: 47.6062,
            longitude: -122.3321,
            calendar: calendar(zone)
        )
        let sunrise = try! XCTUnwrap(day.sunrise)
        let elevation = SolarCalculator.elevation(
            at: sunrise,
            latitude: 47.6062,
            longitude: -122.3321
        )
        // Sunrise is defined at -0.833 degrees, the refraction-corrected horizon.
        XCTAssertEqual(elevation, -0.833, accuracy: 0.3)
    }
}
