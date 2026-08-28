import Foundation

/// Sunrise, sunset, and solar elevation from the NOAA solar position
/// algorithm.
///
/// Deliberately free of HealthKit, CoreLocation, and SwiftUI: the widgets and
/// the complication compile it, and the tests exercise it with no device.
///
/// Everything here is geometry, not a forecast. It says where the sun is, not
/// whether the sky is clear, so a value from this file is the *available*
/// daylight rather than the light that actually reached anyone.
enum SolarCalculator {

    /// Why a day has no sunrise or sunset. Above the polar circles this is the
    /// normal case for months at a time, so it is a state rather than an error.
    enum Condition: Equatable {
        case normal
        /// The sun never sets: every minute of the day is daylight.
        case polarDay
        /// The sun never rises: there is no daylight to be had.
        case polarNight
    }

    /// The sun's schedule for one calendar day at one place.
    struct Day: Equatable {
        var sunrise: Date?
        var sunset: Date?
        var solarNoon: Date
        /// Sun 6° below the horizon in the morning: light enough to be outside.
        var civilDawn: Date?
        /// Sun 6° below the horizon in the evening.
        var civilDusk: Date?
        var condition: Condition
        /// The zone this day was computed in.
        ///
        /// Carried on the value rather than read from the device, because a
        /// polar day's "rest of the day" depends on where midnight falls, and
        /// reading `TimeZone.current` there would silently disagree with the
        /// calendar this `Day` was actually built from.
        var timeZone: TimeZone = .current

        /// Midnight-to-midnight for the local day containing `date`.
        var dayCalendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar
        }

        /// Seconds between sunrise and sunset. A polar day is the whole 24
        /// hours; a polar night is zero.
        var length: TimeInterval {
            switch condition {
            case .polarDay: return 24 * 3600
            case .polarNight: return 0
            case .normal:
                guard let sunrise, let sunset, sunset > sunrise else { return 0 }
                return sunset.timeIntervalSince(sunrise)
            }
        }

        /// Whether `date` falls between sunrise and sunset.
        func isDaylight(at date: Date) -> Bool {
            switch condition {
            case .polarDay: return true
            case .polarNight: return false
            case .normal:
                guard let sunrise, let sunset else { return false }
                return date >= sunrise && date <= sunset
            }
        }

        /// Seconds of daylight still to come after `date`.
        ///
        /// Before sunrise this is the whole day, because none of it has been
        /// spent yet. That matters: someone checking at 6am should be told
        /// there are nine hours available, not that the day is already over.
        func remainingDaylight(after date: Date) -> TimeInterval {
            switch condition {
            case .polarNight:
                return 0
            case .polarDay:
                let endOfDay = dayCalendar.startOfDay(for: date).addingTimeInterval(24 * 3600)
                return max(0, endOfDay.timeIntervalSince(date))
            case .normal:
                guard let sunrise, let sunset else { return 0 }
                if date <= sunrise { return max(0, sunset.timeIntervalSince(sunrise)) }
                return max(0, sunset.timeIntervalSince(date))
            }
        }
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    /// The sun's schedule for the calendar day containing `date`.
    ///
    /// `longitude` is positive east, matching CoreLocation.
    static func day(
        for date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = SolarCalculator.calendar
    ) -> Day {
        let startOfDay = calendar.startOfDay(for: date)
        // NOAA's terms are evaluated at local solar noon rather than at
        // midnight, which is what keeps the answer accurate at high latitudes
        // where the sun's declination moves visibly within a single day.
        let noonGuess = startOfDay.addingTimeInterval(12 * 3600)
        let century = julianCentury(noonGuess)

        let declination = declinationDegrees(century: century)
        let equationOfTime = equationOfTimeMinutes(century: century)

        // Minutes past UTC midnight when the sun crosses the meridian.
        let solarNoonMinutes = 720 - 4 * longitude - equationOfTime
        let solarNoon = utcMinutes(solarNoonMinutes, onDayContaining: startOfDay, calendar: calendar)

        let sunriseAngle = hourAngle(
            latitude: latitude,
            declination: declination,
            zenith: sunriseZenith
        )
        let civilAngle = hourAngle(
            latitude: latitude,
            declination: declination,
            zenith: civilZenith
        )

        var condition: Condition = .normal
        var sunrise: Date?
        var sunset: Date?

        if let sunriseAngle {
            let riseMinutes = 720 - 4 * (longitude + sunriseAngle) - equationOfTime
            let setMinutes = 720 - 4 * (longitude - sunriseAngle) - equationOfTime
            sunrise = utcMinutes(riseMinutes, onDayContaining: startOfDay, calendar: calendar)
            sunset = utcMinutes(setMinutes, onDayContaining: startOfDay, calendar: calendar)
        } else {
            // No hour angle means the sun never reaches the horizon. Which side
            // of the horizon it stays on depends on the hemisphere and season.
            condition = sunIsUpAllDay(latitude: latitude, declination: declination)
                ? .polarDay
                : .polarNight
        }

        var civilDawn: Date?
        var civilDusk: Date?
        if let civilAngle {
            let dawnMinutes = 720 - 4 * (longitude + civilAngle) - equationOfTime
            let duskMinutes = 720 - 4 * (longitude - civilAngle) - equationOfTime
            civilDawn = utcMinutes(dawnMinutes, onDayContaining: startOfDay, calendar: calendar)
            civilDusk = utcMinutes(duskMinutes, onDayContaining: startOfDay, calendar: calendar)
        }

        return Day(
            sunrise: sunrise,
            sunset: sunset,
            solarNoon: solarNoon,
            civilDawn: civilDawn,
            civilDusk: civilDusk,
            condition: condition,
            timeZone: calendar.timeZone
        )
    }

    /// The sun's angle above the horizon, in degrees. Negative is below.
    static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let century = julianCentury(date)
        let declination = declinationDegrees(century: century)
        let equationOfTime = equationOfTimeMinutes(century: century)

        let minutesUTC = minutesPastUTCMidnight(date)
        // True solar time in minutes, wrapped into a single day.
        var trueSolarTime = minutesUTC + equationOfTime + 4 * longitude
        trueSolarTime = trueSolarTime.truncatingRemainder(dividingBy: 1440)
        if trueSolarTime < 0 { trueSolarTime += 1440 }

        // Hour angle: zero at solar noon, negative in the morning.
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let latitudeRadians = radians(latitude)
        let declinationRadians = radians(declination)
        let hourAngleRadians = radians(hourAngle)

        let cosineZenith = sin(latitudeRadians) * sin(declinationRadians)
            + cos(latitudeRadians) * cos(declinationRadians) * cos(hourAngleRadians)
        return 90 - degrees(acos(min(1, max(-1, cosineZenith))))
    }

    /// The sun's declination in degrees, which is what makes days long in June
    /// and short in December.
    static func declination(on date: Date) -> Double {
        declinationDegrees(century: julianCentury(date))
    }

    /// Minutes by which apparent solar time runs ahead of mean solar time.
    /// Always inside roughly ±17 minutes.
    static func equationOfTime(on date: Date) -> Double {
        equationOfTimeMinutes(century: julianCentury(date))
    }

    // MARK: - NOAA terms

    /// Sunrise is defined at 90.833° rather than 90°: half a degree for the
    /// sun's disc and about 34 arcminutes for atmospheric refraction.
    private static let sunriseZenith = 90.833
    private static let civilZenith = 96.0

    private static func julianDay(_ date: Date) -> Double {
        // 2440587.5 is the Julian day of the Unix epoch.
        date.timeIntervalSince1970 / 86400 + 2440587.5
    }

    private static func julianCentury(_ date: Date) -> Double {
        (julianDay(date) - 2451545.0) / 36525
    }

    private static func minutesPastUTCMidnight(_ date: Date) -> Double {
        let julian = julianDay(date)
        let fractional = julian + 0.5 - (julian + 0.5).rounded(.down)
        return fractional * 1440
    }

    /// Geometric mean longitude of the sun, degrees, wrapped to 0..<360.
    private static func meanLongitude(century: Double) -> Double {
        var value = 280.46646 + century * (36000.76983 + century * 0.0003032)
        value.formTruncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func meanAnomaly(century: Double) -> Double {
        357.52911 + century * (35999.05029 - 0.0001537 * century)
    }

    private static func orbitEccentricity(century: Double) -> Double {
        0.016708634 - century * (0.000042037 + 0.0000001267 * century)
    }

    /// Correction for the earth's orbit being an ellipse rather than a circle.
    private static func equationOfCenter(century: Double) -> Double {
        let anomaly = radians(meanAnomaly(century: century))
        return sin(anomaly) * (1.914602 - century * (0.004817 + 0.000014 * century))
            + sin(2 * anomaly) * (0.019993 - 0.000101 * century)
            + sin(3 * anomaly) * 0.000289
    }

    private static func apparentLongitude(century: Double) -> Double {
        let trueLongitude = meanLongitude(century: century) + equationOfCenter(century: century)
        return trueLongitude - 0.00569 - 0.00478 * sin(radians(125.04 - 1934.136 * century))
    }

    /// Mean obliquity of the ecliptic, corrected for nutation.
    private static func obliquity(century: Double) -> Double {
        let seconds = 21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))
        let mean = 23 + (26 + seconds / 60) / 60
        return mean + 0.00256 * cos(radians(125.04 - 1934.136 * century))
    }

    private static func declinationDegrees(century: Double) -> Double {
        let sinDeclination = sin(radians(obliquity(century: century)))
            * sin(radians(apparentLongitude(century: century)))
        return degrees(asin(min(1, max(-1, sinDeclination))))
    }

    private static func equationOfTimeMinutes(century: Double) -> Double {
        let obliquityTerm = tan(radians(obliquity(century: century) / 2))
        let y = obliquityTerm * obliquityTerm
        let longitude = radians(meanLongitude(century: century))
        let anomaly = radians(meanAnomaly(century: century))
        let eccentricity = orbitEccentricity(century: century)

        let value = y * sin(2 * longitude)
            - 2 * eccentricity * sin(anomaly)
            + 4 * eccentricity * y * sin(anomaly) * cos(2 * longitude)
            - 0.5 * y * y * sin(4 * longitude)
            - 1.25 * eccentricity * eccentricity * sin(2 * anomaly)
        return 4 * degrees(value)
    }

    /// Half the angular width of the day, in degrees. Nil when the sun never
    /// reaches `zenith`, which is the polar day and polar night case.
    private static func hourAngle(
        latitude: Double,
        declination: Double,
        zenith: Double
    ) -> Double? {
        let latitudeRadians = radians(latitude)
        let declinationRadians = radians(declination)
        let cosineHourAngle = cos(radians(zenith))
            / (cos(latitudeRadians) * cos(declinationRadians))
            - tan(latitudeRadians) * tan(declinationRadians)
        guard cosineHourAngle >= -1, cosineHourAngle <= 1 else { return nil }
        return degrees(acos(cosineHourAngle))
    }

    /// With no sunrise, the sun is up all day when the hemisphere and the
    /// declination agree in sign: northern summer, or southern summer.
    private static func sunIsUpAllDay(latitude: Double, declination: Double) -> Bool {
        latitude >= 0 ? declination > 0 : declination < 0
    }

    /// Turn "minutes past UTC midnight" into a `Date` on the intended local day.
    ///
    /// The minute count can fall outside 0..<1440 for places far from their
    /// time zone's meridian, so it is applied as an offset from UTC midnight
    /// and allowed to land on the neighbouring day rather than being wrapped.
    private static func utcMinutes(
        _ minutes: Double,
        onDayContaining localStartOfDay: Date,
        calendar: Calendar
    ) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        // The local day can straddle two UTC days. Anchor on the UTC midnight
        // closest to local noon so the offset lands on the right one.
        let localNoon = localStartOfDay.addingTimeInterval(12 * 3600)
        let utcMidnight = utcCalendar.startOfDay(for: localNoon)
        return utcMidnight.addingTimeInterval(minutes * 60)
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
