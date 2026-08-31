import Foundation
import os
import SwiftData

let daylightAppGroupID = "group.com.jackwallner.daylight"
let daylightCachedProKey = "isPro"
let daylightGoalMinutesKey = "dailyGoalMinutes"
let daylightHasRecordedSampleKey = "hasRecordedDaylightSample"
let daylightExcludedSourcesKey = "excludedSourceBundleIDs"
let daylightExcludedSourceNamesKey = "excludedSourceNames"
let daylightHasCompletedSetupKey = "hasCompletedSetup"
let daylightReminderEnabledKey = "reminderEnabled"
let daylightReminderLeadKey = "reminderLeadMinutes"
/// Last known coordinates, cached in the App Group.
///
/// The widgets and the complication need the sun's schedule, and neither can
/// run CoreLocation on its own. The app writes here whenever it gets a fix, so
/// a widget can compute sunset from the last place the phone actually was.
let daylightLatitudeKey = "lastLatitude"
let daylightLongitudeKey = "lastLongitude"
let daylightLocationDateKey = "lastLocationDate"

@MainActor
enum DataService {
    static let appGroupID = daylightAppGroupID

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedDaylightSample.self,
            DailyDaylightRecord.self,
        ])
        let storeURL = containerURL.appendingPathComponent("Daylight.store")
        let configuration = ModelConfiguration(
            "Daylight",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Logger(subsystem: "com.jackwallner.daylight", category: "Data")
                .error("Persistent store failed: \(String(describing: error), privacy: .public)")
            let fallback = ModelConfiguration(
                "DaylightFallback",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Unable to initialize Daylight data store: \(error)")
            }
        }
    }()

    private static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}

enum ProAccess {
    static var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoPro") { return true }
        #endif
        return (UserDefaults(suiteName: daylightAppGroupID) ?? .standard)
            .bool(forKey: daylightCachedProKey)
    }
}

/// The last place the phone knew it was, shared with the widget targets.
///
/// Falls back to a mid-latitude northern default so a widget added before the
/// app has ever had a fix still renders a plausible sun rather than a crash or
/// a blank. The app labels an un-located estimate; the fallback is a shape to
/// draw, not a claim about where anyone is.
struct CachedLocation: Equatable {
    var latitude: Double
    var longitude: Double
    var updated: Date?

    static let fallback = CachedLocation(latitude: 40.0, longitude: -100.0, updated: nil)

    var isReal: Bool { updated != nil }

    static var current: CachedLocation {
        let defaults = UserDefaults(suiteName: daylightAppGroupID) ?? .standard
        guard
            let latitude = defaults.object(forKey: daylightLatitudeKey) as? Double,
            let longitude = defaults.object(forKey: daylightLongitudeKey) as? Double
        else { return .fallback }
        return CachedLocation(
            latitude: latitude,
            longitude: longitude,
            updated: defaults.object(forKey: daylightLocationDateKey) as? Date
        )
    }

    static func store(latitude: Double, longitude: Double, date: Date = .now) {
        let defaults = UserDefaults(suiteName: daylightAppGroupID) ?? .standard
        defaults.set(latitude, forKey: daylightLatitudeKey)
        defaults.set(longitude, forKey: daylightLongitudeKey)
        defaults.set(date, forKey: daylightLocationDateKey)
    }
}
