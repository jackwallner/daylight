# Daylight, Project Guide

The minutes you have spent in daylight today against a target you set, and the
latest you could head out to still reach it before sunset. XcodeGen
project/scheme: `Daylight`, sim lease owners `daylight` and `daylight-watch`.

## Product

The app answers three questions, in this order:

1. How many minutes have I spent in daylight today, against my target?
2. How much daylight is still available before sunset?
3. What is the latest I could head out and still reach my target?

**The first one leads on every surface.** Today, the watch app, the widgets,
and every complication family show the recorded total against the target, with
a progress bar or a gauge. A number climbing toward a goal is worth glancing
at; the daylight remaining only counts down to zero and then says nothing until
tomorrow, which makes it a poor thing to put on a complication.

The third is still the distinctive interaction, and it is what keeps this from
being the twelfth tally app on the store. It is a deadline that moves with the
season, computed from the shortfall against sunset, and it is the reason the
app is useful at 4pm in November rather than only at bedtime. It sits directly
under the headline as the card that tells you what to do about the number
above it.

This ordering was inverted until 2026-08-28: the countdown was the hero
everywhere and the total was a subtitle. If you are tempted to promote the
remaining figure back to the lead, that was tried, and the habit loop is the
reason it changed.

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
- App Store Connect app: `6806112259`
- RevenueCat project `proje7f6e3db`. The entitlement's lookup key is
  `daylight` and `Daylight+` is only its display name, so the
  `StoreService.proEntitlement` constant does not match anything. Nothing reads
  that constant: `isPro` is set from any active entitlement, which is why the
  mismatch has never shown up.
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

None of the three exist yet. App Store Connect has no in-app purchases on the
record, and the RevenueCat project holds only Test Store products keyed
`monthly`, `yearly`, and `lifetime`, attached to no offering. The `default`
offering is empty, so a TestFlight or App Store build reaches the paywall with
nothing to show. Creating the three ASC products, linking them to the
RevenueCat App Store app under their full identifiers, and adding them to
`default` as packages is the work left before the paywall renders off the
simulator.

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
`./scripts/testflight.sh`. The App Store Connect record is `6806112259` and the
1.0 version sits in `PREPARE_FOR_SUBMISSION`. The listing copy, screenshots,
IAP records, and age rating are still unset, so a store submission needs those
before `scripts/asc-submit-for-review.py` will do anything useful.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
