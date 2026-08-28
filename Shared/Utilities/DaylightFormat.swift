import Foundation

enum DaylightFormat {
    /// "1h 20m", "45m". The unit everything in this app is measured in.
    static func minutes(_ value: Double) -> String {
        let total = max(0, Int(value.rounded()))
        let hours = total / 60
        let remainder = total % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    /// Compact enough for a complication: "1h20", "45m".
    static func compactMinutes(_ value: Double) -> String {
        let total = max(0, Int(value.rounded()))
        let hours = total / 60
        let remainder = total % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h\(remainder)"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ interval: TimeInterval) -> String {
        minutes(interval / 60)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// Signed minutes for the seasonal comparison: "+4m", "-11m", "no change".
    static func signedMinutes(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded == 0 { return "no change" }
        return rounded > 0 ? "+\(minutes(Double(rounded)))" : "-\(minutes(Double(-rounded)))"
    }
}
