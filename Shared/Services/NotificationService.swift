import Foundation
import UserNotifications

@MainActor
enum NotificationService {
    static let deadlineIdentifier = "daylight.leaveby.reminder"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) == true
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Fire `leadMinutes` before the last moment the goal is still reachable.
    ///
    /// This is the only notification the app sends, and it is the one that is
    /// worth sending: a reminder after sunset would be a reprimand rather than
    /// a nudge, so nothing schedules once the deadline has passed.
    static func scheduleDeadlineReminder(
        latestStart: Date,
        leadMinutes: Int,
        minutesShort: Double
    ) async {
        cancelDeadlineReminder()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        let fireDate = latestStart.addingTimeInterval(-Double(max(0, leadMinutes)) * 60)
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Daylight is running out"
        content.body = "\(DaylightFormat.minutes(minutesShort)) short of your target. "
            + "Head out by \(DaylightFormat.time(latestStart)) to reach it before sunset."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: deadlineIdentifier,
                content: content,
                trigger: trigger
            )
        )
    }

    static func cancelDeadlineReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [deadlineIdentifier])
    }
}
