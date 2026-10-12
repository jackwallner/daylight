#!/usr/bin/env bash
# Upload an existing archive of Daylight to TestFlight (default build/Daylight.xcarchive)
# with the App Store Connect API key. The shared fleet script does the work; see
# ~/ios/release/testflight.sh for flags and credentials.
cd "$(dirname "$0")/.." || exit 1
exec "$HOME/ios/release/testflight.sh" --project Daylight.xcodeproj --scheme Daylight --upload-only "$@"
