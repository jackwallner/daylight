import SwiftUI

struct WatchDaylightView: View {
    @EnvironmentObject private var settings: DaylightSettings
    @StateObject private var health = HealthKitService.shared
    @State private var now = Date.now

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var snapshot: DaylightSummary.Snapshot {
        health.snapshot(now: now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(DaylightFormat.minutes(snapshot.remainingMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text("daylight left")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))

                deadline

                HStack {
                    Text(DaylightFormat.minutes(snapshot.minutesToday))
                        .font(.headline)
                    Spacer()
                    Text("of \(DaylightFormat.minutes(snapshot.goalMinutes))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: snapshot.goalProgress)
                    .tint(snapshot.metGoal ? Theme.mint : Theme.amber)

                if let sunset = snapshot.solar.sunset {
                    Label(DaylightFormat.time(sunset), systemImage: "sunset.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Daylight")
        .onReceive(tick) { now = $0 }
        .task { await health.refreshCache() }
    }

    @ViewBuilder
    private var deadline: some View {
        let snapshot = snapshot
        if snapshot.metGoal {
            Label("Target reached", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.mint)
        } else if let latestStart = snapshot.latestStart {
            VStack(spacing: 1) {
                Text("Head out by")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(DaylightFormat.time(latestStart))
                    .font(.title3.bold())
            }
        } else {
            Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        }
    }
}
