---
paths:
  - "scripts/asc-*.py"
  - "scripts/rc-setup.py"
  - "scripts/asc_lib.py"
  - "fastlane/**/*"
  - "Shared/Utilities/ScreenshotConfig.swift"
  - "Shared/Services/StoreService.swift"
---

# Daylight: store products and the release checklist

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here.

## Store products

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

## Release checklist

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
