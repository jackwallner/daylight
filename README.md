# Daylight

The minutes you have spent in daylight today against a target you set, and the
latest you could head out to still reach it before sunset. iPhone and Apple
Watch, powered by Apple Health.

Apple Health counts the minutes an Apple Watch recorded you in daylight. This
app gives that number a target to climb toward, then adds the half nobody else
shows: the daylight the sun still has to offer, and the deadline that follows
from it.

- **Today** - minutes in daylight against your target, then the deadline,
  sunrise, sunset, and day length.
- **Head out by** - the latest you could start and still reach your daily
  target. It moves with the season, not the clock.
- **Trends** - daily minutes, streaks, and how today's available daylight
  compares with the same day a month ago.
- **Widgets and a complication** - your progress toward the target on the home
  screen and the wrist.

Time in Daylight is recorded by Apple Watch using its ambient light sensor.
Without one the minutes figure stays at zero and the Today screen says so
directly under the number; everything computed from the sun still works.

Sunrise and sunset are computed on device from an approximate location using
the NOAA solar position algorithm. Nothing leaves the device and there is no
background location tracking.

Not medical advice. The app reports what your devices recorded and what the sun
offers, and makes no claim about mood, sleep, vitamin D, or eyesight.

## Build

```
xcodegen generate
agent-sim checkout daylight
xcodebuild test -project Daylight.xcodeproj -scheme Daylight \
  -destination "id=$(agent-sim udid daylight)"
agent-sim checkin daylight
```
