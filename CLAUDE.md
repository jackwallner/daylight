# Daylight Left — Project Guide

How much daylight is left today, and the latest you could head out to reach
your target before sunset. XcodeGen project/scheme: `Daylight`, sim lease
owners `daylight` and `daylight-watch`.

## Product

Every other app in this category answers one question: how many minutes did
Apple Health record you in daylight? That number alone is a tally, and the App
Store already has a dozen of them.

This app answers three, and the second two are what make it worth opening:

1. How many minutes have I spent in daylight today?
2. How much daylight is still available before sunset?
3. What is the latest I could head out and still reach my target?

The third is the distinctive interaction. It is a deadline that moves with the
season, computed from the shortfall against sunset, and it is the reason the
app is useful at 4pm in November rather than only at bedtime.

## Tech stack and identifiers

- Swift 6, SwiftUI, SwiftData, HealthKit, CoreLocation, WidgetKit,
  WatchConnectivity
- iOS 17+, watchOS 10+ (`HKQuantityTypeIdentifier.timeInDaylight` needs both)
- App: `com.jackwallner.daylight`
- Widget: `com.jackwallner.daylight.widget`
- Watch app: `com.jackwallner.daylight.watch`
- Watch widget: `com.jackwallner.daylight.watch.widget`
- Tests: `com.jackwallner.daylight.tests`
- App Group: `group.com.jackwallner.daylight`
- App Store Connect app: not yet created
- RevenueCat entitlement: `Daylight+` (confirm against the dashboard before the
  first release; `isPro` falls back to any active entitlement, so a mismatch
  would go unnoticed)
- RevenueCat secret key: `~/.daylight_credentials`. Only the `appl_` public key
  belongs in the binary.

## Architecture

Two pure-Swift files carry the product, and both are free of HealthKit,
CoreLocation, and SwiftUI so the widgets compile them and the tests run without
a device:

- `Shared/Utilities/SolarCalculator.swift` — the NOAA solar position algorithm.
  Sunrise, sunset, solar noon, civil twilight, declination, equation of time,
  and elevation, plus the polar day and polar night states. Pinned in tests
  against published times for Seattle, London, Sydney, and Tromsø.
- `Shared/Utilities/DaylightSummary.swift` — the join. Remaining daylight,
  shortfall against the target, the head-out-by deadline, source
  reconciliation, daily totals, streaks, and the month-over-month change in
  available daylight.

`SolarCalculator.Day` carries the time zone it was computed in. Do not reach
for `TimeZone.current` inside it: a polar day's "rest of the day" depends on
where midnight falls, and reading the device zone there silently disagrees with
the calendar the value was built from.

HealthKit is read-only. The app reads `timeInDaylight` with an `HKSampleQuery`
grouped by source, never a statistics collection, because the Sources screen
needs to know which device wrote what. `NSHealthUpdateUsageDescription` is
still required in `Info.plist`: App Store Connect's static analysis sees
`requestAuthorization(toShare:read:)` in the binary and rejects the upload
without it, even though `toShare` is empty.

CoreLocation takes one reduced-accuracy fix and caches the coordinates in the
App Group via `CachedLocation`. The widgets and the complication read that
cache, because neither can run CoreLocation itself. Nothing leaves the device;
the sun's position is computed locally.

WatchConnectivity carries settings and coordinates only, phone to watch, via
`applicationContext`. Daylight samples are never sent: HealthKit already syncs
them between paired devices.

## Access model

Free: daylight remaining, sunrise and sunset, day length, the daily target, the
head-out-by deadline, Apple Health source controls, widgets, complications, and
seven days of history.

Daylight+ unlocks history past seven days, the month-over-month daylight
comparison, and the reminder before the daily deadline.

Store products:

- `com.jackwallner.daylight.monthly`
- `com.jackwallner.daylight.yearly`
- `com.jackwallner.daylight.pro.lifetime`

## App Review constraints

- This is a wellness app with no health claim. Never say it improves mood,
  sleep, eyesight, vitamin D, or seasonal affective disorder, and never imply a
  daylight target is medically recommended. The target is the user's own
  preference.
- Time in Daylight is recorded by Apple Watch. An iPhone-only user sees zero
  minutes, and the Today screen must keep saying so explicitly rather than
  implying they stayed indoors. This is the app's biggest 4.3 and 2.1 exposure:
  the sunrise, sunset, and daylight-remaining half has to stand on its own.
- Sunrise and sunset are calculations, not measurements. They describe the sun,
  not the weather, and the copy should not promise the light was usable.
- Do not put prices, `free`, or discounts in screenshots or screenshot headers.

## Release

Run `xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh`. The App Store Connect record does not exist yet, so
`scripts/asc-*.py` cannot run until it is created and `AppStoreReviewLinks.appStoreID`
is filled in.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
