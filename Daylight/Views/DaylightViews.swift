import SwiftUI
import UIKit
@preconcurrency import RevenueCat

// MARK: - Onboarding

struct DaylightOnboardingView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var location = LocationService.shared
    @State private var page = Self.debugStartPage
    @State private var showPurchase = false

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            healthAccess.tag(1)
            locationAccess.tag(2)
            goal.tag(3)
            plus.tag(4)
        }
        .tabViewStyle(.page)
        .background(Theme.background)
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
    }

    private var welcome: some View {
        OnboardingPage(
            symbol: "sun.max.fill",
            title: "Know what you got, and when to go",
            message: "Your Apple Watch records minutes in daylight. Daylight puts that total against a target you choose, calculates how much light remains, and tells you the latest you could head out to finish before sunset."
        ) {
            OnboardingExampleCard()
            Button("Get started") { page = 1 }
                .buttonStyle(SunButtonStyle())
        }
    }

    private var healthAccess: some View {
        OnboardingPage(
            symbol: "heart.text.square.fill",
            title: "Connect the full picture",
            message: "Daylight asks Apple Health for daylight, sleep, activity, heart, and breathing records. The Daylight+ Personal Daylight Model checks which signals actually line up for you. Everything is read-only, analyzed on this device, and never sent to us. You can choose each type in Apple's permission sheet."
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
            Button("Continue") { page = 4 }
            .buttonStyle(SunButtonStyle())
        }
    }

    private var plus: some View {
        OnboardingPage(
            symbol: "waveform.path.ecg.rectangle.fill",
            title: "Find what lines up for you",
            message: "Daylight+ runs a private model across your records. It highlights only clear relationships and says when none appear. A result might find sleep continuity stands out while heart, breathing, and activity do not. Relationships are not proof of cause or medical advice."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                PlusBenefitRow(symbol: "sparkles", text: "Personal Daylight Model")
                PlusBenefitRow(symbol: "calendar", text: "Full history and seasonal context")
                PlusBenefitRow(symbol: "bell.fill", text: "Deadline reminders")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.isPro {
                Button("Start with Daylight+") { completeSetup() }
                    .buttonStyle(SunButtonStyle())
            } else {
                Button("See Daylight+") { showPurchase = true }
                    .buttonStyle(SunButtonStyle())
                Button("Continue with the free version") { completeSetup() }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func completeSetup() {
        settings.hasCompletedSetup = true
        Task { await health.refreshCache() }
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

private struct OnboardingExampleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EXAMPLE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("44m of 60m")
                    .font(.headline.monospacedDigit())
            }
            ProgressView(value: 44.0, total: 60.0)
                .tint(Theme.amber)
            HStack {
                Label("Head out by", systemImage: "figure.walk")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("4:36 PM")
                    .font(.headline.monospacedDigit())
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: 44 minutes of a 60 minute target. Head out by 4:36 PM.")
    }
}

private struct PlusBenefitRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
    }
}

private struct OnboardingPage<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 24)
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
                    Spacer(minLength: 24)
                    actions
                    Spacer().frame(height: 40)
                }
                .frame(minHeight: geometry.size.height)
                .padding(28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
                // The headline is now the recorded total, so an iPhone-only
                // user leads with a giant zero. Say why immediately rather
                // than four cards further down, where it read as an
                // afterthought to a number that looked like a judgement.
                healthNotice
                deadlineCard
                dayArcCard
                sunCard
                if location.isUsingFallback || location.isAuthorizationDenied { locationNotice }
            }
            .padding(18)
        }
        .background(Theme.background)
        .safeAreaPadding(.bottom, 80)
        .navigationTitle("Today")
        .onReceive(tick) { now = $0 }
        .refreshable {
            LocationService.shared.refresh()
            await health.refreshCache()
        }
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
    }

    /// The number the app exists to grow, and the target that gives it a shape.
    /// The daylight still available is the card below: it is what makes this
    /// number actionable, not what the day is measured by.
    private var headline: some View {
        let snapshot = snapshot
        return VStack(spacing: 6) {
            Text(DaylightFormat.minutes(snapshot.minutesToday))
                .font(.system(size: 62, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.sunGradient)
                .contentTransition(.numericText())
            Text("in daylight today")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("of your \(DaylightFormat.minutes(snapshot.goalMinutes)) target")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            ProgressView(value: snapshot.goalProgress)
                .tint(snapshot.metGoal ? Theme.mint : Theme.amber)
                .padding(.horizontal, 44)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(DaylightFormat.minutes(snapshot.minutesToday)) in daylight today, of your \(DaylightFormat.minutes(snapshot.goalMinutes)) target")
    }

    /// What is still on offer, and the deadline that follows from it. This is
    /// the interaction the rest of the category does not have: not what you
    /// did, but what you still can. The goal ring lives in the headline now, so
    /// every branch here has to name the daylight left in its own words.
    @ViewBuilder
    private var deadlineCard: some View {
        let snapshot = snapshot
        VStack(alignment: .leading, spacing: 10) {
            Label("Before sunset", systemImage: "sunset.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            if snapshot.metGoal {
                Text("Target reached")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.mint)
                Text("\(DaylightFormat.minutes(snapshot.remainingMinutes)) of daylight still to come today.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else if let latestStart = snapshot.latestStart {
                Text("Head out by \(DaylightFormat.time(latestStart))")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short, with \(DaylightFormat.minutes(snapshot.remainingMinutes)) of daylight left. That is the latest you could start and still reach your target before sunset.")
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

    private var noDataNotice: some View {
        let hasPreviousSamples = health.readState == .noDataToday
        return NoticeCard(
            symbol: "applewatch.slash",
            title: hasPreviousSamples ? "No daylight sample today" : "No daylight minutes recorded yet",
            message: hasPreviousSamples
                ? "Apple Health has not provided a reading for today. Zero does not mean you stayed inside. Sunrise, sunset, and daylight remaining still work."
                : "Apple Watch records this number automatically. Zero means Apple Health has no reading yet, not that you stayed inside. Sunrise, sunset, and daylight remaining still work.",
            actionTitle: "Review Health access"
        ) { openAppSettings() }
    }

    @ViewBuilder
    private var healthNotice: some View {
        if let error = health.lastError {
            NoticeCard(
                symbol: "exclamationmark.triangle.fill",
                title: "Apple Health could not be read",
                message: error,
                actionTitle: "Try again"
            ) {
                Task { await health.refreshCache() }
            }
        } else {
            switch health.readState {
            case .notDetermined:
                NoticeCard(
                    symbol: "heart.text.square.fill",
                    title: "Connect Apple Health to see your minutes",
                    message: "Apple Watch records Time in Daylight. Daylight only reads that number and never writes anything back.",
                    actionTitle: "Connect Apple Health"
                ) {
                    Task {
                        try? await health.requestAuthorization()
                        await health.refreshCache()
                    }
                }
            case .noData, .noDataToday:
                noDataNotice
            case .receiving:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var locationNotice: some View {
        if location.isAuthorizationDenied {
            NoticeCard(
                symbol: "location.slash",
                title: "Location access is off",
                message: location.isUsingFallback
                    ? "Sunrise and sunset use an approximate default. Enable location in Settings for times based on where you are."
                    : "Sunrise and sunset use your last known location. Enable location in Settings to keep the times current."
            )
        } else {
            NoticeCard(
                symbol: "location.slash",
                title: "Using an approximate location",
                message: "Sunrise and sunset are estimated from a default position until location access is granted, so the times above may be well off. Turn it on in Settings."
            )
        }
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

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(Theme.textSecondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 4)
                }
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
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var personalModel: DaylightSummary.PersonalHealthModel?
    @State private var isModelLoading = false
    @State private var modelLoadFailed = false

    /// Seven days is free. Everything past it is the paid tier, because the
    /// interesting comparisons only exist once there is a season of data.
    private static let freeDays = 7
    private static let ranges = [7, 30, 90, 365]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker
                summaryCard
                if store.isPro {
                    personalModelCard
                    seasonCard
                }
                if let loadError {
                    NoticeCard(
                        symbol: "exclamationmark.triangle.fill",
                        title: "History could not be loaded",
                        message: loadError,
                        actionTitle: "Try again"
                    ) { Task { await load() } }
                } else if isLoading && totals.isEmpty {
                    ProgressView("Loading history")
                        .frame(maxWidth: .infinity)
                        .padding(32)
                } else {
                    chart
                }
                if !store.isPro { upsell }
            }
            .padding(18)
        }
        .background(Theme.background)
        .safeAreaPadding(.bottom, 80)
        .navigationTitle("Trends")
        .task(id: range) { await load() }
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $range) {
                ForEach(Self.ranges, id: \.self) { days in
                    let label = days == 365 ? "1y" : "\(days)d"
                    if days == Self.freeDays {
                        Text(label).tag(days)
                    } else {
                        Label(label, systemImage: "lock.fill")
                            .accessibilityLabel("\(label), requires Daylight+")
                            .tag(days)
                    }
                }
            }
            .pickerStyle(.segmented)
            if !store.isPro {
                Label("Longer history requires Daylight+", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
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
        let change = DaylightSummary.availableDaylightChangeSincePreviousMonth(
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

    private var personalModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Daylight Model", systemImage: "waveform.path.ecg.rectangle.fill")
                .font(.headline)
            if isModelLoading && personalModel == nil {
                ProgressView("Checking your Health records")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let relationship = personalModel?.strongestClearRelationship {
                Text("One clear relationship")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.dusk)
                    .textCase(.uppercase)
                Text(healthSignalTitle(relationship.signal))
                    .font(.title2.bold())
                Text(relationshipSummary(relationship))
                    .font(.callout)
                Text(modelCoverageSummary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else if let personalModel, personalModel.evaluatedCount > 0 {
                Text("No clear relationship yet")
                    .font(.title2.bold())
                Text("The model checked \(personalModel.evaluatedCount) signals and none separated clearly from ordinary variation in your records.")
                    .font(.callout)
            } else {
                Text("Build your personal model")
                    .font(.title2.bold())
                Text(modelLoadFailed
                     ? "Health data was not available. Review access, then try again."
                     : "Daylight needs at least 14 paired days for each signal. Missing records are left out, never treated as zero.")
                    .font(.callout)
                Button("Review Health access") {
                    Task {
                        try? await health.requestAuthorization()
                        await loadPersonalModel()
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.amber)
            }

            DisclosureGroup("How this is calculated") {
                Text("The model compares recorded daylight with sleep, steps, exercise, active energy, resting heart rate, heart-rate variability, and respiratory rate. It shows a relationship only when a conservative uncertainty check, adjusted for all eight signals, excludes no relationship. Everything runs on this device. A relationship is not proof that daylight caused the result or medical advice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 6)
            }
            .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var modelCoverageSummary: String {
        guard let personalModel,
              let strongest = personalModel.strongestClearRelationship
        else { return "" }
        let otherCount = max(0, personalModel.evaluatedCount - 1)
        let otherText = otherCount == 1 ? "1 other signal" : "\(otherCount) other signals"
        return "Based on \(strongest.sampleCount) paired days. No other clear relationship appeared across \(otherText)."
    }

    private func healthSignalTitle(_ signal: DaylightSummary.HealthSignal) -> String {
        switch signal {
        case .sleepDuration: "Sleep duration"
        case .sleepContinuity: "Sleep continuity"
        case .steps: "Steps"
        case .exerciseMinutes: "Exercise time"
        case .activeEnergy: "Active energy"
        case .restingHeartRate: "Resting heart rate"
        case .heartRateVariability: "Heart-rate variability"
        case .respiratoryRate: "Respiratory rate"
        }
    }

    private func relationshipSummary(
        _ relationship: DaylightSummary.HealthRelationship
    ) -> String {
        guard let difference = relationship.outcomeDifference else {
            return "This signal moved with your recorded daylight."
        }
        let direction = difference >= 0 ? "higher" : "lower"
        let amount = abs(difference)
        switch relationship.signal {
        case .sleepDuration:
            let duration = DaylightFormat.minutes(amount)
            let comparison = difference >= 0 ? "longer" : "shorter"
            return "Your recorded sleep averaged \(duration) \(comparison) after higher-daylight days."
        case .sleepContinuity:
            let points = Int((amount * 100).rounded())
            let comparison = difference >= 0 ? "more" : "less"
            return "Your recorded sleep was \(points) percentage points \(comparison) continuous after higher-daylight days."
        case .steps:
            let count = Int(amount.rounded()).formatted()
            let comparison = difference >= 0 ? "more" : "fewer"
            return "Your step count averaged \(count) \(comparison) on higher-daylight days."
        case .exerciseMinutes:
            return "Your exercise time averaged \(DaylightFormat.minutes(amount)) \(direction) on higher-daylight days."
        case .activeEnergy:
            return "Your active energy averaged \(Int(amount.rounded())) calories \(direction) on higher-daylight days."
        case .restingHeartRate:
            return "Your resting heart rate averaged \(amount.formatted(.number.precision(.fractionLength(1)))) beats per minute \(direction) on higher-daylight days."
        case .heartRateVariability:
            return "Your heart-rate variability averaged \(amount.formatted(.number.precision(.fractionLength(1)))) milliseconds \(direction) on higher-daylight days."
        case .respiratoryRate:
            return "Your respiratory rate averaged \(amount.formatted(.number.precision(.fractionLength(1)))) breaths per minute \(direction) on higher-daylight days."
        }
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
            Text("Find your clearest pattern")
                .font(.headline)
            Text("Daylight+ privately checks how your daylight lines up with sleep, activity, heart, and breathing records. It also unlocks full history, seasonal context, and deadline reminders.")
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
        isLoading = true
        defer { isLoading = false }
        do {
            totals = try await health.fetchHistory(days: days)
            loadError = nil
            if store.isPro { await loadPersonalModel() }
        } catch {
            loadError = "Apple Health did not return your daylight history. Check Health access, then try again."
        }
    }

    private func loadPersonalModel() async {
        isModelLoading = true
        defer { isModelLoading = false }
        do {
            personalModel = try await health.fetchPersonalHealthModel(days: max(90, range))
            modelLoadFailed = false
        } catch {
            personalModel = nil
            modelLoadFailed = true
        }
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(total.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(
                            "\(DaylightFormat.minutes(total.minutes)) in daylight, target \(DaylightFormat.minutes(total.goalMinutes))"
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily minutes in daylight over the selected range")
    }
}

// MARK: - Settings

struct DaylightSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: DaylightSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var health = HealthKitService.shared
    @StateObject private var location = LocationService.shared
    @State private var showPurchase = false
    @State private var reminderChangeInFlight = false
    @State private var reminderPermissionDenied = false

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
                        step: 5,
                        onEditingChanged: { isEditing in
                            guard !isEditing else { return }
                            health.refreshDerivedCache()
                        }
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
                Text("Daylight reads Time in Daylight plus sleep, activity, heart, and breathing records for the Personal Daylight Model. It never writes to Apple Health, uploads Health data, or treats missing data as zero.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Location") {
                if location.isAuthorizationDenied {
                    Button("Open Settings", action: openAppSettings)
                    Text("Location access is off. Enable it in Settings to use your current sunrise and sunset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Use my location") { location.requestAccess() }
                }
                LabeledContent("Sunset times", value: locationStatusLabel)
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
                                reminderPermissionDenied = !granted
                                if granted { await health.refreshCache() }
                            } else {
                                settings.reminderEnabled = false
                                reminderPermissionDenied = false
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
                    .onChange(of: settings.reminderLeadMinutes) { _, _ in
                        Task { await health.rescheduleDeadlineReminder() }
                    }
                }
                if !store.isPro {
                    Text("Included with Daylight+.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if reminderPermissionDenied {
                    Button("Open notification settings", action: openAppSettings)
                    Text("Notifications are off for Daylight. Enable them in Settings to use the reminder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Daylight+") {
                LabeledContent("Status", value: store.isPro ? "Active" : "Free")
                Text("Includes the Personal Daylight Model, full history, seasonal context, and deadline reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(store.isPro ? "View purchase options" : "See Daylight+") { showPurchase = true }
                Button {
                    Task { await store.restore() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Text("Restore purchases")
                    }
                }
                .disabled(store.isLoading)
                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                Link("Privacy policy", destination: DaylightLinks.privacyPolicy)
                Link("Support", destination: DaylightLinks.support)
                Text("Sunrise and sunset are calculated from your approximate location. Daylight minutes come from Apple Health. Daylight reports what your devices recorded and what the sun offers. It does not diagnose, treat, or prevent anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .safeAreaPadding(.bottom, 80)
        .tint(Theme.amber)
        .sheet(isPresented: $showPurchase) { DaylightPurchaseView() }
        .task { await refreshReminderPermission() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshReminderPermission() }
        }
    }

    private var healthStatusLabel: String {
        switch health.readState {
        case .notDetermined: "Not connected"
        case .receiving: "Receiving"
        case .noData: "No samples yet"
        case .noDataToday: "No sample today"
        }
    }

    private var locationStatusLabel: String {
        if location.isAuthorizationDenied {
            return location.isUsingFallback ? "Approximate" : "Last known"
        }
        return location.isUsingFallback ? "Approximate" : "Your location"
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshReminderPermission() async {
        let status = await NotificationService.authorizationStatus()
        reminderPermissionDenied = settings.reminderEnabled && status == .denied
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
                        set: {
                            settings.setSourceIncluded($0, bundleID: source.bundleID, name: source.name)
                            health.refreshDerivedCache()
                        }
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
    @State private var selectedPackageIdentifier: String?
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.sunGradient)
                    Text("Daylight+")
                        .font(.largeTitle.bold())
                    Text("See which parts of your Health record actually line up with daylight. Today's total, moving deadline, and seven-day history stay free.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)

                    VStack(alignment: .leading, spacing: 12) {
                        PlusBenefitRow(symbol: "waveform.path.ecg.rectangle.fill", text: "Personal model across 8 Health signals")
                        PlusBenefitRow(symbol: "checkmark.seal.fill", text: "Only clear relationships are highlighted")
                        PlusBenefitRow(symbol: "lock.shield.fill", text: "Calculated privately on this device")
                        PlusBenefitRow(symbol: "calendar", text: "Full history and seasonal context")
                        PlusBenefitRow(symbol: "bell.fill", text: "Deadline reminders")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(store.packages, id: \.identifier) { package in
                        Button {
                            selectedPackageIdentifier = package.identifier
                        } label: {
                            DaylightPlanCard(
                                title: package.daylightDisplayName,
                                price: package.daylightPriceLabel,
                                detail: package.daylightPackageKind == .lifetime
                                    ? "One-time purchase"
                                    : store.eligibleIntroLabel(for: package),
                                isSelected: selectedPackageIdentifier == package.identifier
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoading)
                    }

                    if store.packages.isEmpty {
                        if store.isLoadingProducts {
                            ProgressView("Loading plans")
                        } else if store.errorMessage != nil {
                            Text("Purchase options are unavailable right now.")
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.textSecondary)
                            Button("Try again") { store.start(forceRefresh: true) }
                        } else {
                            ProgressView("Loading plans")
                        }
                    }

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.red)
                    }

                    if let selectedPackage {
                        billedAmount(for: selectedPackage)
                    }

                    Button {
                        guard let package = selectedPackage else { return }
                        Task {
                            if await store.purchase(package) == .purchased { dismiss() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isLoading { ProgressView().tint(.white) }
                            Text(purchaseButtonLabel)
                        }
                    }
                    .buttonStyle(SunButtonStyle())
                    .disabled(selectedPackage == nil || store.isLoading)

                    Text(purchaseDisclosure)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)

                    Button {
                        Task {
                            isRestoring = true
                            await store.restore()
                            isRestoring = false
                        }
                    } label: {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text("Restore purchases")
                        }
                    }
                    .disabled(store.isLoading)
                    HStack {
                        Link("Terms", destination: DaylightLinks.standardEULA)
                        Text("·")
                        Link("Privacy", destination: DaylightLinks.privacyPolicy)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
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
        .onAppear { selectDefaultPackage() }
        .onChange(of: store.packages.map(\.identifier)) { _, _ in selectDefaultPackage() }
        .task {
            if store.packages.isEmpty && !store.isLoadingProducts {
                store.start(forceRefresh: true)
            }
        }
        .onAppear { store.trackPaywallImpression(id: "daylight_paywall") }
        .onDisappear { store.clearError() }
    }

    private var selectedPackage: Package? {
        if let selectedPackageIdentifier,
           let selected = store.packages.first(where: { $0.identifier == selectedPackageIdentifier }) {
            return selected
        }
        return store.yearlyPackage ?? store.packages.first
    }

    private var purchaseButtonLabel: String {
        if store.isLoading { return "Processing..." }
        guard let selectedPackage else { return "Choose a plan" }
        return ConversionCopy.ctaLabel(
            trialLabel: store.eligibleIntroLabel(for: selectedPackage),
            priceLabel: selectedPackage.daylightPriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selectedPackage)
        )
    }

    private var purchaseDisclosure: String {
        if selectedPackage?.daylightPackageKind == .lifetime {
            return "\(selectedPackage?.daylightPriceLabel ?? ""). One-time purchase with no subscription or automatic renewal."
        }
        if let selectedPackage {
            return ConversionCopy.disclosure(
                trialLabel: store.eligibleIntroLabel(for: selectedPackage),
                priceLabel: selectedPackage.daylightPriceLabel,
                eligibleForTrial: store.isEligibleForIntroOffer(selectedPackage)
            )
        }
        return "Prices are shown before you buy and vary by region."
    }

    private func billedAmount(for package: Package) -> some View {
        return VStack(spacing: 4) {
            Text("BILLED AMOUNT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(ConversionCopy.billedAmount(priceLabel: package.daylightPriceLabel))
                .font(.title2.bold())
            Text(package.daylightPackageKind == .lifetime
                 ? "One-time purchase"
                 : ConversionCopy.billedNote(
                    trialLabel: store.eligibleIntroLabel(for: package),
                    eligibleForTrial: store.isEligibleForIntroOffer(package)
                 ))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func selectDefaultPackage() {
        guard let package = store.yearlyPackage ?? store.packages.first else {
            selectedPackageIdentifier = nil
            return
        }
        guard let selectedPackageIdentifier,
              store.packages.contains(where: { $0.identifier == selectedPackageIdentifier }) else {
            self.selectedPackageIdentifier = package.identifier
            return
        }
    }
}

private struct DaylightPlanCard: View {
    let title: String
    let price: String
    let detail: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.amber : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.mint)
                }
            }
            Spacer(minLength: 8)
            Text(price).fontWeight(.semibold)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Theme.amber : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(price)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
