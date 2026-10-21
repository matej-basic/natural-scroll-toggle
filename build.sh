#!/bin/bash
# Builds NaturalScrollToggle and packages it as build/NaturalScrollToggle.app.
# Usage: ./build.sh            build and sign
#        ./build.sh install    build, then copy to /Applications (quits a running copy)
set -euo pipefail
cd "$(dirname "$0")"

NAME="NaturalScrollToggle"
VERSION="${VERSION:-0.2.0}"
APP="build/$NAME.app"

echo "Building (release)..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$NAME"

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>Natural Scroll Toggle</string>
    <key>CFBundleIdentifier</key><string>com.matejbasic.NaturalScrollToggle</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "Signing (ad hoc)..."
codesign --force --sign - "$APP"

echo
echo "Done: $(pwd)/$APP"
echo "Run it with:  open $APP"
echo "Install with: ./build.sh install"

if [ "${1:-}" = "install" ]; then
    DEST="/Applications"
    echo
    echo "Installing to $DEST..."
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "${DEST:?}/$NAME.app"
    cp -R "$APP" "$DEST/"
    echo "Installed to $DEST/$NAME.app"
    echo "Start it with:  open $DEST/$NAME.app"
fi
