#!/bin/zsh
# Baut Mittelklick.app (Universal: Apple Silicon und Intel) nach build/, mit --install zusätzlich nach ~/Applications und startet es,
# mit --zip zusätzlich build/Mittelklick-<Version>.zip für ein GitHub-Release.
set -euo pipefail
cd "${0:A:h}"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --disable-sandbox $ARCHS
BIN="$(swift build -c release --disable-sandbox $ARCHS --show-bin-path)/Mittelklick"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

APP=build/Mittelklick.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Mit Developer ID signieren, falls vorhanden: Dann bleibt die Bedienungshilfen-Freigabe über Neubauten erhalten.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" --options runtime "$APP"
echo "Gebaut: $APP ($VERSION)"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/Mittelklick-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Archiv: $ZIP"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Mittelklick || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Mittelklick.app
    ditto "$APP" ~/Applications/Mittelklick.app
    open ~/Applications/Mittelklick.app
    echo "Installiert: ~/Applications/Mittelklick.app"
fi
