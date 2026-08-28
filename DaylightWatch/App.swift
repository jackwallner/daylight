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
                    await HealthKitService.shared.synchronizeAuthorization()
                    await HealthKitService.shared.refreshCache()
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
