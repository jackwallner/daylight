import SwiftData
import SwiftUI
import WatchKit

@main
struct DaylightWatchApp: App {
    @StateObject private var settings = DaylightSettings.shared

    init() {
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchDaylightView() }
                .environmentObject(settings)
                .task {
                    #if DEBUG
                    // Same seeding the iOS app does under a screenshot launch.
                    // Without it a watch capture has no goal and no cached
                    // coordinates, so the fixtures render against a fallback
                    // location and the deadline never appears.
                    if ScreenshotConfig.isEnabled {
                        settings.dailyGoalMinutes = 60
                        CachedLocation.store(latitude: 47.6062, longitude: -122.3321)
                    }
                    #endif
                    await HealthKitService.shared.synchronizeAuthorization()
                    await HealthKitService.shared.refreshCache()
                    scheduleRefresh()
                }
        }
        .modelContainer(DataService.sharedModelContainer)
        .backgroundTask(.appRefresh("daylight.refresh")) {
            await HealthKitService.shared.refreshCache()
            await MainActor.run { scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 30 * 60),
            userInfo: nil
        ) { _ in }
    }
}
