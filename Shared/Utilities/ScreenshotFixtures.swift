import Foundation

#if DEBUG
enum ScreenshotFixtures {
    /// A believable morning walk plus a lunch break, written by a watch.
    static func samples(from start: Date, to end: Date) -> [DaylightSummary.Sample] {
        let dayStart = DateHelpers.startOfDay()
        func window(_ startHour: Double, _ minutes: Double) -> DaylightSummary.Sample {
            let begin = dayStart.addingTimeInterval(startHour * 3600)
            return DaylightSummary.Sample(
                start: begin,
                end: begin.addingTimeInterval(minutes * 60),
                minutes: minutes,
                sourceBundleID: "com.apple.health.watch",
                sourceName: "Apple Watch"
            )
        }
        let all = [window(7.5, 14), window(12.25, 21), window(17.5, 9)]
        return all.filter { $0.start >= start && $0.start < end }
    }

    static func history(days: Int) -> [DaylightSummary.DailyTotal] {
        let minutes = [44.0, 12, 61, 8, 35, 52, 19, 73, 26, 41, 5, 58, 30, 47]
        let available = [612.0, 610, 608, 605, 603, 600, 598, 595, 593, 590, 588, 585, 583, 580]
        let count = max(days, 1)
        return (0..<count).map { offset in
            let index = (minutes.count - count + offset).modulo(minutes.count)
            let date = DateHelpers.daysAgo(offset)
            return DaylightSummary.DailyTotal(
                dayKey: DateHelpers.dayKey(for: date),
                date: date,
                minutes: minutes[index],
                availableMinutes: available[index],
                goalMinutes: 20
            )
        }
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
#endif
