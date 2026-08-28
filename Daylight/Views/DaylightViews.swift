import SwiftUI

// MARK: - Onboarding

struct DaylightOnboardingView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var location = LocationService.shared
    @State private var page = Self.debugStartPage

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            healthAccess.tag(1)
            locationAccess.tag(2)
            goal.tag(3)
        }
        .tabViewStyle(.page)
        .background(Theme.background)
    }

    private var welcome: some View {
        OnboardingPage(
            symbol: "sun.max.fill",
            title: "Daylight Left",
            message: "Apple Health counts the minutes you spend in daylight. This app adds the half nobody shows you: how much daylight is still available today, and the time you would have to head out to reach your target before sunset."
        ) {
            Button("Get started") { page = 1 }
                .buttonStyle(SunButtonStyle())
        }
    }

    private var healthAccess: some View {
        OnboardingPage(
            symbol: "heart.text.square.fill",
            title: "Read your daylight minutes",
            message: "Your Apple Watch records Time in Daylight using its ambient light sensor. This app reads that number and never writes anything back. Without a watch that records it, the sunrise and sunset half still works."
        ) {
            Button("Connect Apple Health") {
                Task {
                    try? await health.requestAuthorization()
                    await health.refreshCache()
                    page = 2
                }
            }
            .buttonStyle(SunButtonStyle())
            Button("Skip for now") { page = 2 }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var locationAccess: some View {
        OnboardingPage(
            symbol: "location.fill",
            title: "Work out your sunset",
            message: "One approximate location fix is enough to compute sunrise and sunset where you are. The maths runs on this device, nothing is sent anywhere, and there is no background tracking."
        ) {
            Button("Use my location") {
                location.requestAccess()
                page = 3
            }
            .buttonStyle(SunButtonStyle())
            Button("Skip for now") { page = 3 }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var goal: some View {
        OnboardingPage(
            symbol: "target",
            title: "Pick a daily target",
            message: "Somewhere to aim. This is your own preference, not a recommendation or a threshold, and you can change it any time in Settings."
        ) {
            VStack(spacing: 8) {
                Text(DaylightFormat.minutes(settings.dailyGoalMinutes))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.amber)
                Slider(
                    value: $settings.dailyGoalMinutes,
                    in: DaylightSettings.goalRange,
                    step: 5
                )
                .tint(Theme.amber)
            }
            Button("Start") {
                settings.hasCompletedSetup = true
                Task { await health.refreshCache() }
            }
            .buttonStyle(SunButtonStyle())
        }
    }

    /// DEBUG hook so a headless run can screenshot any single page.
    private static var debugStartPage: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OnboardingPage"),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1])
        else { return 0 }
        return value
        #else
        return 0
        #endif
    }
}

private struct OnboardingPage<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 62))
                .foregroundStyle(Theme.sunGradient)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            actions
            Spacer().frame(height: 40)
        }
        .padding(28)
    }
}

// MARK: - Today

struct DaylightTodayView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @StateObject private var health = HealthKitService.shared
    @StateObject private var location = LocationService.shared
    @State private var now = Date.now
    @State private var showPurchase = false

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var snapshot: DaylightSummary.Snapshot {
        health.snapshot(now: now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headline
                deadlineCard
                dayArcCard
                sunCard
                if health.readState == .noData { noWatchNotice }
                if location.isUsingFallback { locationNotice }
            }
            .padding(18)
        }
        .background(Theme.background)
        .navigationTitle("Today")
        .onReceive(tick) { now = $0 }
        .refreshable {
            LocationService.shared.refresh()
            await health.refreshCache()
        }
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
    }

    /// The one number the app exists to show, and the one that gives it meaning.
    private var headline: some View {
        VStack(spacing: 6) {
            Text(DaylightFormat.minutes(snapshot.remainingMinutes))
                .font(.system(size: 62, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.sunGradient)
                .contentTransition(.numericText())
            Text("of daylight left today")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("\(DaylightFormat.minutes(snapshot.minutesToday)) spent in it so far")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }

    /// The forecast. This is the interaction the rest of the category does not
    /// have: not what you did, but what you still can.
    @ViewBuilder
    private var deadlineCard: some View {
        let snapshot = snapshot
        VStack(alignment: .leading, spacing: 10) {
            Label("Your target", systemImage: "target")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            if snapshot.metGoal {
                Text("Target reached")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.mint)
                Text("\(DaylightFormat.minutes(snapshot.minutesToday)) of your \(DaylightFormat.minutes(snapshot.goalMinutes)) target, with \(DaylightFormat.minutes(snapshot.remainingMinutes)) of daylight still to come.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else if let latestStart = snapshot.latestStart {
                Text("Head out by \(DaylightFormat.time(latestStart))")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short. That is the latest you could start and still reach your target before sunset.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else if snapshot.isGoalStillPossible {
                Text("Still reachable")
                    .font(.title2.bold())
                Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short, and \(DaylightFormat.minutes(snapshot.remainingMinutes)) of daylight left.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Not today")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.warning)
                Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short with \(DaylightFormat.minutes(snapshot.remainingMinutes)) of daylight left. Tomorrow offers \(DaylightFormat.minutes(tomorrowAvailable)).")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }

            ProgressView(value: snapshot.goalProgress)
                .tint(snapshot.metGoal ? Theme.mint : Theme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var dayArcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The day so far")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            DayArc(solar: snapshot.solar, now: now)
                .frame(height: 46)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var sunCard: some View {
        let solar = snapshot.solar
        return VStack(spacing: 12) {
            switch solar.condition {
            case .polarDay:
                Label("The sun does not set today", systemImage: "sun.max.circle.fill")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .polarNight:
                VStack(alignment: .leading, spacing: 6) {
                    Label("The sun does not rise today", systemImage: "moon.stars.fill")
                        .font(.callout.weight(.medium))
                    if let dawn = solar.civilDawn, let dusk = solar.civilDusk {
                        Text("Usable twilight from \(DaylightFormat.time(dawn)) to \(DaylightFormat.time(dusk)).")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .normal:
                HStack {
                    SunStat(
                        symbol: "sunrise.fill",
                        label: "Sunrise",
                        value: solar.sunrise.map(DaylightFormat.time) ?? "—"
                    )
                    Spacer()
                    SunStat(
                        symbol: "sunset.fill",
                        label: "Sunset",
                        value: solar.sunset.map(DaylightFormat.time) ?? "—"
                    )
                    Spacer()
                    SunStat(
                        symbol: "clock.fill",
                        label: "Day length",
                        value: DaylightFormat.minutes(solar.length / 60)
                    )
                }
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var noWatchNotice: some View {
        NoticeCard(
            symbol: "applewatch.slash",
            title: "No daylight minutes yet",
            message: "Time in Daylight is recorded by Apple Watch. Without one, the sunrise, sunset, and daylight-remaining figures above still work, but the minutes you have spent outside will stay at zero."
        )
    }

    private var locationNotice: some View {
        NoticeCard(
            symbol: "location.slash",
            title: "Using an approximate location",
            message: "Sunrise and sunset are estimated from a default position until location access is granted, so the times above may be well off. Turn it on in Settings."
        )
    }

    private var tomorrowAvailable: Double {
        let coordinates = location.coordinates
        let tomorrow = now.addingTimeInterval(24 * 3600)
        return SolarCalculator.day(
            for: tomorrow,
            latitude: coordinates.latitude,
            longitude: coordinates.longitude
        ).length / 60
    }
}

private struct SunStat: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.amber)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct NoticeCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Sunrise to sunset as a horizontal band, with a marker for now.
///
/// A bar rather than a ring: the day is a line with two ends, and a ring would
/// imply the quantity wraps around.
private struct DayArc: View {
    let solar: SolarCalculator.Day
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 18
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.elevated)
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.dayGradient)
                    .frame(width: max(0, width * progress), height: height)
                Circle()
                    .fill(Theme.gold)
                    .frame(width: 14, height: 14)
                    .offset(x: max(0, min(width - 14, width * progress - 7)), y: 2)
                    .shadow(color: Theme.amber.opacity(0.7), radius: 6)

                HStack {
                    Text(startLabel)
                    Spacer()
                    Text(endLabel)
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .offset(y: height + 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day progress: \(DaylightFormat.percent(progress)) of today's daylight has passed")
    }

    /// How much of the daylight window has already gone.
    private var progress: Double {
        switch solar.condition {
        case .polarNight:
            return 1
        case .polarDay:
            let start = solar.dayCalendar.startOfDay(for: now)
            return min(1, max(0, now.timeIntervalSince(start) / (24 * 3600)))
        case .normal:
            guard let sunrise = solar.sunrise, let sunset = solar.sunset, sunset > sunrise else {
                return 0
            }
            let total = sunset.timeIntervalSince(sunrise)
            return min(1, max(0, now.timeIntervalSince(sunrise) / total))
        }
    }

    private var startLabel: String {
        solar.sunrise.map(DaylightFormat.time) ?? "—"
    }

    private var endLabel: String {
        solar.sunset.map(DaylightFormat.time) ?? "—"
    }
}

// MARK: - Trends

struct DaylightTrendsView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @State private var totals: [DaylightSummary.DailyTotal] = []
    @State private var range = 7
    @State private var showPurchase = false

    /// Seven days is free. Everything past it is the paid tier, because the
    /// interesting comparisons only exist once there is a season of data.
    private static let freeDays = 7
    private static let ranges = [7, 30, 90, 365]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker
                summaryCard
                if store.isPro { seasonCard }
                chart
                if !store.isPro { upsell }
            }
            .padding(18)
        }
        .background(Theme.background)
        .navigationTitle("Trends")
        .task(id: range) { await load() }
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(Self.ranges, id: \.self) { days in
                Text(days == 365 ? "1y" : "\(days)d").tag(days)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: range) { _, value in
            guard value > Self.freeDays, !store.isPro else { return }
            range = Self.freeDays
            showPurchase = true
        }
    }

    private var summaryCard: some View {
        HStack {
            TrendStat(
                value: DaylightFormat.minutes(DaylightSummary.average(totals)),
                label: "Daily average"
            )
            Spacer()
            TrendStat(
                value: "\(DaylightSummary.daysMetGoal(totals))",
                label: "Days on target"
            )
            Spacer()
            TrendStat(
                value: "\(DaylightSummary.currentStreak(totals))",
                label: "Current streak"
            )
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// The number that only the sun can tell you, and the reason this screen is
    /// worth opening in February.
    private var seasonCard: some View {
        let coordinates = LocationService.shared.coordinates
        let change = DaylightSummary.availableDaylightChange(
            days: 30,
            latitude: coordinates.latitude,
            longitude: coordinates.longitude
        )
        return VStack(alignment: .leading, spacing: 6) {
            Label("Since a month ago", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(DaylightFormat.signedMinutes(change))
                .font(.title.bold())
                .foregroundStyle(change >= 0 ? Theme.mint : Theme.dusk)
            Text(change >= 0
                 ? "Today offers that much more daylight than the same day last month."
                 : "Today offers that much less daylight than the same day last month.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minutes in daylight")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HistoryBars(totals: totals.reversed())
                .frame(height: 150)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var upsell: some View {
        VStack(spacing: 10) {
            Text("See the whole year")
                .font(.headline)
            Text("Daylight+ unlocks history past seven days, the seasonal comparison, and a reminder before your daily deadline.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Button(store.shortConversionCTALabel) { showPurchase = true }
                .buttonStyle(SunButtonStyle())
        }
        .padding(18)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func load() async {
        let days = store.isPro ? range : min(range, Self.freeDays)
        totals = (try? await health.fetchHistory(days: days)) ?? []
    }
}

private struct TrendStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(Theme.amber)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryBars: View {
    let totals: [DaylightSummary.DailyTotal]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(totals.map(\.minutes).max() ?? 1, 1)
            let spacing: CGFloat = totals.count > 40 ? 1 : 4
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(totals) { total in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(total.metGoal ? Theme.amber : Theme.dusk.opacity(0.55))
                        .frame(height: max(2, geometry.size.height * total.minutes / maximum))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily minutes in daylight over the selected range")
    }
}

// MARK: - Settings

struct DaylightSettingsView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var location = LocationService.shared
    @State private var showPurchase = false
    @State private var reminderChangeInFlight = false

    var body: some View {
        Form {
            Section("Daily target") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Target")
                        Spacer()
                        Text(DaylightFormat.minutes(settings.dailyGoalMinutes))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.dailyGoalMinutes,
                        in: DaylightSettings.goalRange,
                        step: 5
                    )
                }
                Text("Your own preference for how much daylight to aim for. It is not a recommendation, a dose, or a safety threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Health") {
                Button("Connect or review access") {
                    Task {
                        try? await health.requestAuthorization()
                        await health.refreshCache()
                    }
                }
                NavigationLink("Included sources") { DaylightSourcesView() }
                LabeledContent("Daylight data", value: healthStatusLabel)
                Text("Daylight Left only reads Time in Daylight. It never writes to Apple Health.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Location") {
                Button("Use my location") { location.requestAccess() }
                LabeledContent("Sunset times", value: location.isUsingFallback ? "Approximate" : "Your location")
                Text("Used once to compute sunrise and sunset on this device. Nothing is sent anywhere and there is no background tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminder") {
                Toggle("Remind me before the deadline", isOn: Binding(
                    get: { settings.reminderEnabled },
                    set: { enabled in
                        guard !reminderChangeInFlight else { return }
                        guard !enabled || store.isPro else {
                            showPurchase = true
                            return
                        }
                        reminderChangeInFlight = true
                        Task {
                            if enabled {
                                let granted = await NotificationService.requestAuthorization()
                                settings.reminderEnabled = granted
                                if granted { await health.refreshCache() }
                            } else {
                                settings.reminderEnabled = false
                                NotificationService.cancelDeadlineReminder()
                            }
                            reminderChangeInFlight = false
                        }
                    }
                ))
                if settings.reminderEnabled {
                    Stepper(
                        "\(settings.reminderLeadMinutes) minutes before",
                        value: $settings.reminderLeadMinutes,
                        in: 5...120,
                        step: 5
                    )
                }
                if !store.isPro {
                    Text("Included with Daylight+.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Daylight+") {
                LabeledContent("Status", value: store.isPro ? "Active" : "Free")
                Button(store.isPro ? "Manage purchase" : "See Daylight+") { showPurchase = true }
                Button("Restore purchases") { Task { await store.restore() } }
            }

            Section("About") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                Link("Privacy policy", destination: DaylightLinks.privacyPolicy)
                Link("Support", destination: DaylightLinks.support)
                Text("Sunrise and sunset are calculated from your approximate location. Daylight minutes come from Apple Health. Daylight Left reports what your devices recorded and what the sun offers. It does not diagnose, treat, or prevent anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
    }

    private var healthStatusLabel: String {
        switch health.readState {
        case .notDetermined: "Not connected"
        case .receiving: "Receiving"
        case .noData: "No samples yet"
        }
    }
}

struct DaylightSourcesView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @StateObject private var health = HealthKitService.shared

    var body: some View {
        List {
            Section {
                Text("Every included source contributes once. A phone and a watch from the same app are collapsed into a single row, so nothing is counted twice.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Sources today") {
                if health.sources.isEmpty {
                    Text("No daylight samples today.")
                        .foregroundStyle(.secondary)
                }
                ForEach(health.sources) { source in
                    Toggle(isOn: Binding(
                        get: { !settings.excludedSourceBundleIDs.contains(source.bundleID) },
                        set: { settings.setSourceIncluded($0, bundleID: source.bundleID, name: source.name) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(source.name)
                            Text(DaylightFormat.minutes(source.minutes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sources")
    }
}

// MARK: - Purchase

struct DaylightPurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.sunGradient)
                    Text("Daylight+")
                        .font(.largeTitle.bold())
                    Text("Today's numbers stay free. Upgrade for history past seven days, the seasonal comparison, and a reminder before your daily deadline.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(store.packages, id: \.identifier) { package in
                        Button {
                            Task {
                                if await store.purchase(package) == .purchased { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(package.daylightDisplayName).font(.headline)
                                    if let trial = store.eligibleIntroLabel(for: package) {
                                        Text(trial).font(.caption).foregroundStyle(Theme.mint)
                                    }
                                }
                                Spacer()
                                Text(package.daylightPriceLabel).fontWeight(.semibold)
                            }
                            .padding(18)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }

                    if store.packages.isEmpty {
                        ProgressView("Loading plans")
                            .task { store.start(forceRefresh: true) }
                    }

                    Text("Subscriptions renew automatically until cancelled. Cancel at least 24 hours before the period ends in your Apple ID settings. Prices are shown before you buy and vary by region.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)

                    Button("Restore purchases") { Task { await store.restore() } }
                    HStack {
                        Link("Terms", destination: DaylightLinks.standardEULA)
                        Text("·")
                        Link("Privacy", destination: DaylightLinks.privacyPolicy)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    if let error = store.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(22)
            }
            .defaultScrollAnchor(.top)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { store.trackPaywallImpression(id: "daylight_paywall") }
    }
}

struct SunButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(Theme.sunGradient, in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
