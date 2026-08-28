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

All three exist in App Store Connect (monthly $5.99, yearly $29.99 with a
one-week free trial in all 175 territories, lifetime $59.99) and are linked into
RevenueCat's `default` offering as `$rc_monthly`, `$rc_annual`, and
`$rc_lifetime`, all attached to the `daylight` entitlement. `scripts/rc-setup.py`
is idempotent and verifies through the public offerings endpoint the app itself
uses.

The RevenueCat project also still holds three **Test Store** products keyed
`monthly`, `yearly`, and `lifetime`. Those are not the shipping products and are
attached to nothing. Do not delete them without checking, and do not confuse
them for the real ones when reading the dashboard.

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
1.0 version sits in `PREPARE_FOR_SUBMISSION`.

`scripts/asc-readiness.py` is the checklist. It reads the live record and prints
what is still missing, and its `EXPECTED_*` constants are the contract: six
`APP_IPHONE_67` screenshots and one `APP_WATCH_SERIES_10`.

Screenshots are captured headless with the app's own launch arguments:
`-ScreenshotTab N` for a populated tab, `-OnboardingPage N` for a single
onboarding page, `-PaywallSnapshot` for the paywall against mock products. Under
any of those, `ScreenshotConfig.isEnabled` turns on the HealthKit fixtures and
seeds a 60-minute target, which is deliberately above the 44 minutes the
fixtures record so captures land on the head-out-by state rather than an
already-met target. Normalize iPhone frames to 1320x2868 RGB and sync with
`~/ios/appstore-screenshots/bin/asc-sync-screenshots`, never a repo-local
uploader.

`fastlane/review/paywall.png` is the App Review screenshot for all three
products, uploaded by `scripts/asc-finish-products.py`. It goes stale invisibly:
re-render it from `-PaywallSnapshot` whenever the paywall or a price moves.

The API rate-limits hard during a metadata push. A 429 means wait, not retry
immediately, and `asc_lib` now backs off on 429 and 5xx for about two minutes
before giving up.

The first IAP cannot be attached to a submission over the public API. That step
is manual in the App Store Connect UI; see the `ios-dev` skill.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
