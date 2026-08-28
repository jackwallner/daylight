import Foundation
import os
import WatchConnectivity

private let watchSyncLogger = Logger(subsystem: "com.jackwallner.daylight", category: "WatchSync")

/// Settings the phone pushes to the watch.
///
/// Daylight minutes are deliberately absent. HealthKit already syncs the
/// samples between paired devices, so shipping them over WatchConnectivity
/// would mean a second copy that can disagree with the first.
///
/// Coordinates ride along because the watch cannot get a useful location fix on
/// its own without draining the battery, and it needs one to know when the sun
/// sets.
struct WatchSettingsPayload: Sendable, Equatable {
    var dailyGoalMinutes: Double?
    var isPro: Bool?
    var hasCompletedSetup: Bool?
    var excludedSourceBundleIDs: [String]?
    var excludedSourceNames: [String: String]?
    var latitude: Double?
    var longitude: Double?

    init(
        dailyGoalMinutes: Double? = nil,
        isPro: Bool? = nil,
        hasCompletedSetup: Bool? = nil,
        excludedSourceBundleIDs: [String]? = nil,
        excludedSourceNames: [String: String]? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.dailyGoalMinutes = dailyGoalMinutes
        self.isPro = isPro
        self.hasCompletedSetup = hasCompletedSetup
        self.excludedSourceBundleIDs = excludedSourceBundleIDs
        self.excludedSourceNames = excludedSourceNames
        self.latitude = latitude
        self.longitude = longitude
    }

    init?(context: [String: Any]) {
        dailyGoalMinutes = context[daylightGoalMinutesKey] as? Double
        isPro = context[daylightCachedProKey] as? Bool
        hasCompletedSetup = context[daylightHasCompletedSetupKey] as? Bool
        excludedSourceBundleIDs = context[daylightExcludedSourcesKey] as? [String]
        excludedSourceNames = context[daylightExcludedSourceNamesKey] as? [String: String]
        latitude = context[daylightLatitudeKey] as? Double
        longitude = context[daylightLongitudeKey] as? Double
        guard dailyGoalMinutes != nil || isPro != nil || latitude != nil else { return nil }
    }

    var dictionary: [String: Any] {
        var value: [String: Any] = [:]
        if let dailyGoalMinutes { value[daylightGoalMinutesKey] = dailyGoalMinutes }
        if let isPro { value[daylightCachedProKey] = isPro }
        if let hasCompletedSetup { value[daylightHasCompletedSetupKey] = hasCompletedSetup }
        if let excludedSourceBundleIDs { value[daylightExcludedSourcesKey] = excludedSourceBundleIDs }
        if let excludedSourceNames { value[daylightExcludedSourceNamesKey] = excludedSourceNames }
        if let latitude { value[daylightLatitudeKey] = latitude }
        if let longitude { value[daylightLongitudeKey] = longitude }
        return value
    }
}

final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncService()

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    func push(settings: WatchSettingsPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        do {
            try session.updateApplicationContext(settings.dictionary)
        } catch {
            watchSyncLogger.error("Settings sync failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    private func apply(_ context: [String: Any]) {
        guard let payload = WatchSettingsPayload(context: context) else { return }
        Task { @MainActor in DaylightSettings.shared.apply(payload) }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            watchSyncLogger.error("Session activation failed: \(String(describing: error), privacy: .public)")
            return
        }
        #if os(watchOS)
        apply(session.receivedApplicationContext)
        #else
        Task { @MainActor in self.push(settings: DaylightSettings.shared.watchPayload) }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
