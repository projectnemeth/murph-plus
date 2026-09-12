#!/bin/sh
# scripts/install-to-devices.sh — build a signed app and put it on the phone.
#
# One command, because the failure this guards against is silent: installing a
# rebuilt app that carries the same build number as the one already on the
# Watch, and never noticing the Watch kept running the old code. Bumping is
# therefore not a step you can forget — it happens here, before the build.
#
# The watch app rides inside the phone app at MurphPlus.app/Watch, and watchOS
# is supposed to copy it across once it sees the phone holding a newer build.
# In practice that did not happen for a development-signed build, and installing
# by hand from the Watch app's Available Apps list failed outright with "This
# app could not be installed at this time." So this installs the watch app
# directly over the debug connection instead, which works, rather than trusting
# a propagation step with no way to tell whether it ran.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# The signing team is passed on the command line rather than written into
# project.yml, so the committed project stays free of one machine's account.
TEAM=${DEVELOPMENT_TEAM:-K8ZFCMC7ND}
DERIVED=${DERIVED_DATA:-/tmp/murph-device-build}

device=${1:-}
watch=${2:-}
if [ -z "$device" ]; then
    echo "usage: $0 <iphone-device-id> [watch-device-id]" >&2
    echo "find both with: xcrun devicectl list devices" >&2
    exit 2
fi

sh scripts/bump-build.sh
xcodegen generate

xcodebuild -project MurphPlus.xcodeproj -scheme MurphPlus -configuration Debug \
    -destination "platform=iOS,id=$device" \
    -derivedDataPath "$DERIVED" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates build

app="$DERIVED/Build/Products/Debug-iphoneos/MurphPlus.app"

# Read the number back out of the built product rather than trusting the one
# just written: this is the value the Watch will actually compare against, and
# a build setting that failed to reach the Info.plist is the exact bug this
# script exists to prevent.
echo "installed build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
echo "embedded watch build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Watch/MurphPlusWatch.app/Info.plist")"

xcrun devicectl device install app --device "$device" "$app"

if [ -n "$watch" ]; then
    xcrun devicectl device install app --device "$watch" "$app/Watch/MurphPlusWatch.app"
else
    echo "note: no watch id given, so the Watch still holds whatever it had." >&2
    echo "      re-run with the watch id as a second argument." >&2
fi
