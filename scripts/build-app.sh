#!/bin/bash
# Builds Kibbit.app into ./build. Pass --install to copy it to /Applications.
# VERSION and BUILD_NUMBER set the bundle version (release CI passes the git tag).
# UNIVERSAL=1 builds for Apple Silicon and Intel (each arch separately, then lipo, which
# works with only the Command Line Tools, unlike a multi-arch `swift build`).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    for arch in arm64 x86_64; do swift build -c release --arch "$arch"; done
    BIN=".build/universal/Kibbit"
    mkdir -p "$(dirname "$BIN")"
    lipo -create -output "$BIN" \
        "$(swift build -c release --arch arm64 --show-bin-path)/Kibbit" \
        "$(swift build -c release --arch x86_64 --show-bin-path)/Kibbit"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/Kibbit"
fi
APP="build/Kibbit.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kibbit"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN" --render-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kibbit</string>
    <key>CFBundleDisplayName</key><string>Kibbit</string>
    <key>CFBundleIdentifier</key><string>dev.kibbit.Kibbit</string>
    <key>CFBundleExecutable</key><string>Kibbit</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Kibbit 2>/dev/null || true
    rm -rf /Applications/Kibbit.app
    cp -R "$APP" /Applications/
    open /Applications/Kibbit.app
    echo "Installed to /Applications/Kibbit.app"
fi
