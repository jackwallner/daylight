import Foundation
import SwiftData

/// One Apple Health daylight sample, cached so the widgets can read it.
///
/// Widgets cannot query HealthKit, so the app writes what it read into the App
/// Group store and the widget targets read from there.
@Model
final class CachedDaylightSample {
    @Attribute(.unique) var id: String
    var start: Date
    var end: Date
    var minutes: Double
    var sourceBundleID: String
    var sourceName: String

    init(
        id: String,
        start: Date,
        end: Date,
        minutes: Double,
        sourceBundleID: String,
        sourceName: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.minutes = minutes
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }
}

/// A day's rolled-up total, kept so history and the complication do not have to
/// replay every sample.
@Model
final class DailyDaylightRecord {
    @Attribute(.unique) var dateString: String
    var date: Date
    var minutes: Double
    /// Daylight the sun offered that day, in minutes.
    var availableMinutes: Double
    var goalMinutes: Double
    var lastUpdated: Date

    init(
        date: Date,
        minutes: Double = 0,
        availableMinutes: Double = 0,
        goalMinutes: Double = 0
    ) {
        let normalized = DateHelpers.startOfDay(date)
        self.dateString = DateHelpers.dayKey(for: normalized)
        self.date = normalized
        self.minutes = minutes
        self.availableMinutes = availableMinutes
        self.goalMinutes = goalMinutes
        self.lastUpdated = .now
    }
}
