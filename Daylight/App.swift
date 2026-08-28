import SwiftData
import SwiftUI

@main
struct DaylightApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = DaylightSettings.shared
    @StateObject private var store = StoreService.shared

    init() {
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    store.start()
                    #if DEBUG
                    if ScreenshotConfig.isEnabled {
                        settings.hasCompletedSetup = true
                        // Above the 44 minutes the fixtures record, so captures
                        // land on the head-out-by state. At the default 20 the
                        // target is always already met and the deadline card,
                        // which is the thing worth showing, never renders.
                        settings.dailyGoalMinutes = 60
                        CachedLocation.store(latitude: 47.6062, longitude: -122.3321)
                    }
                    #endif
                    await HealthKitService.shared.synchronizeAuthorization()
                    LocationService.shared.refresh()
                    await HealthKitService.shared.refreshCache()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        LocationService.shared.refresh()
                        await HealthKitService.shared.refreshCache()
                    }
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}

private struct RootView: View {
    @EnvironmentObject private var settings: DaylightSettings

    var body: some View {
        if Self.paywallSnapshot {
            DaylightPurchaseView()
        } else if !settings.hasCompletedSetup && !ScreenshotConfig.isEnabled {
            DaylightOnboardingView()
        } else {
            DaylightTabView(initialTab: Self.screenshotTab ?? 0)
        }
    }

    static var paywallSnapshot: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PaywallSnapshot")
        #else
        false
        #endif
    }

    static var screenshotTab: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ScreenshotTab"), index + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
    }
}

struct DaylightTabView: View {
    let initialTab: Int
    @State private var selection: Int

    init(initialTab: Int = 0) {
        self.initialTab = initialTab
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DaylightTodayView() }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)
            NavigationStack { DaylightTrendsView() }
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                .tag(1)
            NavigationStack { DaylightSettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .tint(Theme.amber)
    }
}
