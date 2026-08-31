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
                    Text(DaylightFormat.minutes(snapshot.minutesToday))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text(headlineSubtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    ProgressView(value: snapshot.goalProgress)
                        .tint(snapshot.metGoal ? Theme.mint : Theme.amber)
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                        .accessibilityLabel("Daily goal progress")
                        .accessibilityValue("\(Int((snapshot.goalProgress * 100).rounded())) percent")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headlineAccessibilityLabel)

                if health.readState == .notDetermined {
                    Button("Connect Apple Health") {
                        Task {
                            try? await health.requestAuthorization()
                            await health.refreshCache()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.amber)
                }

                deadline

                HStack {
                    Label(DaylightFormat.minutes(snapshot.remainingMinutes), systemImage: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("\(DaylightFormat.minutes(snapshot.remainingMinutes)) of daylight left")
                    Spacer()
                    if let sunset = snapshot.solar.sunset {
                        Label(DaylightFormat.time(sunset), systemImage: "sunset.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("Sunset at \(DaylightFormat.time(sunset))")
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .onReceive(tick) { now = $0 }
        .task { await health.refreshCache() }
    }

    private var headlineSubtitle: String {
        switch health.readState {
        case .notDetermined:
            "Health access needed"
        case .noData:
            "No samples yet · goal \(DaylightFormat.minutes(snapshot.goalMinutes))"
        case .noDataToday:
            "No sample today · goal \(DaylightFormat.minutes(snapshot.goalMinutes))"
        case .receiving:
            "of \(DaylightFormat.minutes(snapshot.goalMinutes)) today"
        }
    }

    private var headlineAccessibilityLabel: String {
        switch health.readState {
        case .notDetermined:
            "Apple Health access is needed to read daylight minutes"
        case .noData:
            "No daylight samples yet. Goal \(DaylightFormat.minutes(snapshot.goalMinutes))"
        case .noDataToday:
            "No daylight sample today. Goal \(DaylightFormat.minutes(snapshot.goalMinutes))"
        case .receiving:
            "\(DaylightFormat.minutes(snapshot.minutesToday)) in daylight today, of \(DaylightFormat.minutes(snapshot.goalMinutes))"
        }
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
        } else if snapshot.isGoalStillPossible {
            Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        } else {
            VStack(spacing: 1) {
                Text("Not enough daylight")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                Text("\(DaylightFormat.minutes(snapshot.minutesToGoal)) short")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
