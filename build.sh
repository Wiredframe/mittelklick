#!/bin/zsh
# Builds Mittelklick.app (universal: Apple silicon and Intel) into build/. --install also copies it to ~/Applications and
# launches it, --zip also creates build/Mittelklick-<version>.zip for a GitHub release.
set -euo pipefail
cd "${0:A:h}"

ARCHS=(--arch arm64 --arch x86_64)
# Otherwise SwiftPM records the deployment target as the SDK version and macOS shows the app in the legacy look
# (small traffic lights, old controls). Linking with the real SDK version gets the current design.
SDK="$(xcrun --show-sdk-version)"
FLAGS=(-c release --disable-sandbox $ARCHS -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK")
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/Mittelklick"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

APP=build/Mittelklick.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Sign with a Developer ID if available, so the Accessibility permission survives rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" --options runtime "$APP"
echo "Built: $APP ($VERSION)"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/Mittelklick-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Archive: $ZIP"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Mittelklick || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Mittelklick.app
    ditto "$APP" ~/Applications/Mittelklick.app
    open ~/Applications/Mittelklick.app
    echo "Installed: ~/Applications/Mittelklick.app"
fi
