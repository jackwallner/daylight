import Combine
import SwiftUI
import WidgetKit

enum AppAppearance: Int, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class DaylightSettings: ObservableObject {
    static let shared = DaylightSettings()

    /// A modest, reachable default. It is a personal target the user picks, not
    /// a dose, a recommendation, or a threshold with any claim attached.
    static let defaultGoalMinutes = 20.0
    static let goalRange: ClosedRange<Double> = 5...240
    /// How long before the "leave by" deadline the reminder fires.
    static let defaultReminderLead = 30

    @Published var hasCompletedSetup: Bool { didSet { persistAndSync() } }
    @Published var dailyGoalMinutes: Double { didSet { persistAndSync() } }
    @Published var excludedSourceBundleIDs: Set<String> { didSet { persistAndSync() } }
    @Published private(set) var excludedSourceNames: [String: String]
    @Published var appearance: AppAppearance { didSet { persistAndSync() } }
    @Published var reminderEnabled: Bool { didSet { persistAndSync() } }
    @Published var reminderLeadMinutes: Int { didSet { persistAndSync() } }
    @Published var cachedIsPro: Bool

    private let defaults: UserDefaults
    private var isInitializing = true

    private init() {
        defaults = UserDefaults(suiteName: daylightAppGroupID) ?? .standard
        hasCompletedSetup = defaults.bool(forKey: daylightHasCompletedSetupKey)
        dailyGoalMinutes = defaults.object(forKey: daylightGoalMinutesKey) as? Double
            ?? Self.defaultGoalMinutes
        excludedSourceBundleIDs = Set(defaults.stringArray(forKey: daylightExcludedSourcesKey) ?? [])
        excludedSourceNames = defaults.dictionary(forKey: daylightExcludedSourceNamesKey)
            as? [String: String] ?? [:]
        appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system
        reminderEnabled = defaults.bool(forKey: daylightReminderEnabledKey)
        reminderLeadMinutes = defaults.object(forKey: daylightReminderLeadKey) as? Int
            ?? Self.defaultReminderLead
        cachedIsPro = ProAccess.isPro
        isInitializing = false
    }

    func setSourceIncluded(_ included: Bool, bundleID: String, name: String) {
        if included {
            excludedSourceBundleIDs.remove(bundleID)
            excludedSourceNames.removeValue(forKey: bundleID)
        } else {
            excludedSourceBundleIDs.insert(bundleID)
            excludedSourceNames[bundleID] = name
        }
        defaults.set(excludedSourceNames, forKey: daylightExcludedSourceNamesKey)
    }

    func apply(_ payload: WatchSettingsPayload) {
        if let value = payload.dailyGoalMinutes { dailyGoalMinutes = value }
        if let value = payload.excludedSourceBundleIDs { excludedSourceBundleIDs = Set(value) }
        if let value = payload.excludedSourceNames {
            excludedSourceNames = value
            defaults.set(value, forKey: daylightExcludedSourceNamesKey)
        }
        if let value = payload.isPro {
            defaults.set(value, forKey: daylightCachedProKey)
            cachedIsPro = value
        }
        if let latitude = payload.latitude, let longitude = payload.longitude {
            CachedLocation.store(latitude: latitude, longitude: longitude)
        }
        if payload.hasCompletedSetup == true { hasCompletedSetup = true }
        WidgetCenter.shared.reloadAllTimelines()
    }

    var watchPayload: WatchSettingsPayload {
        let location = CachedLocation.current
        return WatchSettingsPayload(
            dailyGoalMinutes: dailyGoalMinutes,
            isPro: ProAccess.isPro,
            hasCompletedSetup: hasCompletedSetup,
            excludedSourceBundleIDs: Array(excludedSourceBundleIDs),
            excludedSourceNames: excludedSourceNames,
            latitude: location.isReal ? location.latitude : nil,
            longitude: location.isReal ? location.longitude : nil
        )
    }

    private func persistAndSync() {
        guard !isInitializing else { return }
        defaults.set(hasCompletedSetup, forKey: daylightHasCompletedSetupKey)
        defaults.set(dailyGoalMinutes, forKey: daylightGoalMinutesKey)
        defaults.set(Array(excludedSourceBundleIDs), forKey: daylightExcludedSourcesKey)
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(reminderEnabled, forKey: daylightReminderEnabledKey)
        defaults.set(reminderLeadMinutes, forKey: daylightReminderLeadKey)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchSyncService.shared.push(settings: watchPayload)
        #endif
    }
}
