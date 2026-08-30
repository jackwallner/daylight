import Foundation
import HealthKit
import os
import SwiftData
import WidgetKit

private final class HealthObserverCompletion: @unchecked Sendable {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    func call() {
        callback()
    }
}

/// Why the app might have nothing to show.
///
/// The distinction matters more here than in a logging app: a user with no
/// supporting watch will never have data, and telling them "0 minutes" would be
/// a lie about their day rather than a fact about their sensors.
enum HealthReadState: Equatable {
    case notDetermined
    case receiving
    /// Authorized, but Apple Health holds no daylight samples at all yet.
    case noData
    /// Apple Health has provided samples before, but none exist for today.
    case noDataToday
}

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    static let maximumHistoryDays = 3650

    @Published var isAuthorized = false
    @Published private(set) var todaySamples: [DaylightSummary.Sample] = []
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var hasEverReadSamples: Bool

    private let store = HKHealthStore()
    /// iOS 17 / watchOS 10. Written by Apple Watch from its ambient light
    /// sensor, in minutes, as a cumulative type.
    private let daylightType = HKQuantityType(.timeInDaylight)
    private let logger = Logger(subsystem: "com.jackwallner.daylight", category: "HealthKit")
    private let defaults = UserDefaults(suiteName: daylightAppGroupID) ?? .standard
    private var observerInstalled = false
    private static let hasEverReadSamplesKey = "hasEverReadDaylightSamples"

    var readState: HealthReadState {
        guard isAuthorized else { return .notDetermined }
        if !todaySamples.isEmpty { return .receiving }
        return hasEverReadSamples ? .noDataToday : .noData
    }

    private init() {
        hasEverReadSamples = defaults.bool(forKey: Self.hasEverReadSamplesKey)
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            hasEverReadSamples = true
        }
    }

    /// This app never writes daylight. It asks with an empty `toShare` set, and
    /// the Info.plist still carries `NSHealthUpdateUsageDescription` because
    /// App Store Connect's static analysis sees `requestAuthorization(toShare:
    /// read:)` in the binary and rejects the upload without it (error 90683).
    func requestAuthorization() async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: [daylightType])
        isAuthorized = true
        enableBackgroundDelivery()
    }

    func synchronizeAuthorization() async {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: [daylightType]) { value, _ in
                continuation.resume(returning: value)
            }
        }
        if status == .unnecessary {
            isAuthorized = true
            enableBackgroundDelivery()
        }
    }

    /// Raw samples in a window, one entry per source per interval.
    ///
    /// A grouped `HKSampleQuery` rather than a statistics collection: a sum
    /// cannot say which device wrote what, and the Sources screen needs both.
    func fetchSamples(from start: Date, to end: Date) async throws -> [DaylightSummary.Sample] {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.samples(from: start, to: end)
        }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: daylightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    let value = error as NSError
                    // "Not determined" is the pre-permission state, not a
                    // failure worth surfacing.
                    if value.domain == HKError.errorDomain,
                       value.code == HKError.errorAuthorizationNotDetermined.rawValue {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let mapped = (samples as? [HKQuantitySample] ?? []).map { sample in
                    let source = sample.sourceRevision.source
                    return DaylightSummary.Sample(
                        start: sample.startDate,
                        end: sample.endDate,
                        minutes: sample.quantity.doubleValue(for: .minute()),
                        sourceBundleID: source.bundleIdentifier,
                        sourceName: source.name
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func refreshCache(now: Date = .now) async {
        let start = DateHelpers.startOfDay(now)
        do {
            let samples = try await fetchSamples(from: start, to: DateHelpers.endOfDay(now))
            if !samples.isEmpty {
                hasEverReadSamples = true
                defaults.set(true, forKey: Self.hasEverReadSamplesKey)
            }
            todaySamples = samples
            lastRefreshed = now
            lastError = nil
            writeCache(now: now)
            #if os(iOS)
            await scheduleReminderIfNeeded(now: now)
            #endif
        } catch {
            logger.error("Daylight refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Daylight minutes could not be read from Apple Health."
        }
    }

    // MARK: - Derived values

    var minutesToday: Double {
        DaylightSummary.totalMinutes(
            todaySamples,
            excludingSourceBundleIDs: DaylightSettings.shared.excludedSourceBundleIDs
        )
    }

    var sources: [DaylightSummary.Source] {
        DaylightSummary.sources(todaySamples)
    }

    func snapshot(now: Date = .now) -> DaylightSummary.Snapshot {
        let location = CachedLocation.current
        return DaylightSummary.snapshot(
            minutesToday: minutesToday,
            goalMinutes: DaylightSettings.shared.dailyGoalMinutes,
            solar: SolarCalculator.day(
                for: now,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            now: now
        )
    }

    /// Per-day totals for the history and trends screens.
    func fetchHistory(days: Int, now: Date = .now) async throws -> [DaylightSummary.DailyTotal] {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return ScreenshotFixtures.history(days: days) }
        #endif
        let count = max(days, 1)
        let start = DateHelpers.daysAgo(count - 1, from: now)
        let samples = try await fetchSamples(from: start, to: DateHelpers.endOfDay(now))
        let location = CachedLocation.current
        let totals = DaylightSummary.dailyTotals(
            samples,
            days: count,
            goalMinutes: DaylightSettings.shared.dailyGoalMinutes,
            latitude: location.latitude,
            longitude: location.longitude,
            now: now,
            excludingSourceBundleIDs: DaylightSettings.shared.excludedSourceBundleIDs
        )
        let records = (try? DataService.sharedModelContainer.mainContext.fetch(
            FetchDescriptor<DailyDaylightRecord>()
        )) ?? []
        var historicalGoals: [String: Double] = [:]
        for record in records where record.goalMinutes > 0 {
            historicalGoals[record.dateString] = record.goalMinutes
        }
        return DaylightSummary.applyingHistoricalGoals(totals, goalsByDay: historicalGoals)
    }

    // MARK: - Cache and observers

    private func writeCache(now: Date) {
        let context = DataService.sharedModelContainer.mainContext
        if let cached = try? context.fetch(FetchDescriptor<CachedDaylightSample>()) {
            cached.forEach(context.delete)
        }
        let excluded = DaylightSettings.shared.excludedSourceBundleIDs
        for (index, sample) in todaySamples.enumerated()
        where !DaylightSummary.isSourceExcluded(sample.sourceBundleID, excluded: excluded) {
            context.insert(CachedDaylightSample(
                id: "\(DateHelpers.dayKey(for: sample.start))-\(index)",
                start: sample.start,
                end: sample.end,
                minutes: sample.minutes,
                sourceBundleID: sample.sourceBundleID,
                sourceName: sample.sourceName
            ))
        }

        let snapshot = snapshot(now: now)
        let key = DateHelpers.dayKey(for: now)
        let descriptor = FetchDescriptor<DailyDaylightRecord>(
            predicate: #Predicate { $0.dateString == key }
        )
        let record = (try? context.fetch(descriptor).first) ?? DailyDaylightRecord(date: now)
        if record.modelContext == nil { context.insert(record) }
        record.minutes = snapshot.minutesToday
        record.availableMinutes = snapshot.availableMinutes
        record.goalMinutes = snapshot.goalMinutes
        record.lastUpdated = now
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Rebuild values derived from settings without re-querying HealthKit.
    /// Source changes need this immediately so widgets do not keep the old sum.
    func refreshDerivedCache(now: Date = .now) {
        writeCache(now: now)
        #if os(iOS)
        Task { await rescheduleDeadlineReminder(now: now) }
        #endif
    }

    #if os(iOS)
    func rescheduleDeadlineReminder(now: Date = .now) async {
        await scheduleReminderIfNeeded(now: now)
    }

    /// Schedule the "leave by" nudge, which is the one notification this app
    /// has any business sending.
    private func scheduleReminderIfNeeded(now: Date) async {
        let settings = DaylightSettings.shared
        guard settings.reminderEnabled, ProAccess.isPro else {
            NotificationService.cancelDeadlineReminder()
            return
        }
        let snapshot = snapshot(now: now)
        guard let latestStart = snapshot.latestStart else {
            NotificationService.cancelDeadlineReminder()
            return
        }
        await NotificationService.scheduleDeadlineReminder(
            latestStart: latestStart,
            leadMinutes: settings.reminderLeadMinutes,
            minutesShort: snapshot.minutesToGoal
        )
    }
    #endif

    private func enableBackgroundDelivery() {
        guard !observerInstalled, HKHealthStore.isHealthDataAvailable() else { return }
        observerInstalled = true
        store.enableBackgroundDelivery(for: daylightType, frequency: .hourly) { _, _ in }
        let query = HKObserverQuery(sampleType: daylightType, predicate: nil) { [weak self] _, completion, _ in
            let observerCompletion = HealthObserverCompletion(completion)
            Task { @MainActor in
                await self?.refreshCache()
                observerCompletion.call()
            }
        }
        store.execute(query)
    }
}
