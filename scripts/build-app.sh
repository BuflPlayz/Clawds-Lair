#!/bin/zsh
# Builds "Clawd's Lair.app" into ./build. Pass --install to also copy it to ~/Applications, or
# --zip to package it as build/Clawds-Lair-<version>.zip for a GitHub release.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=1.0
# A universal binary, so it runs on Apple silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/ClawdsLair"

APP="build/Clawd's Lair.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClawdsLair"

# The app icon is an Icon Composer document; actool turns it into Assets.car + AppIcon.icns.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Clawd's Lair</string>
    <key>CFBundleDisplayName</key><string>Clawd's Lair</string>
    <key>CFBundleIdentifier</key><string>io.github.buflplayz.clawdslair</string>
    <key>CFBundleExecutable</key><string>ClawdsLair</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Extended attributes (Finder info, iCloud's file-provider tags) make codesign fail.
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/"Clawd's Lair.app"
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Clawd's Lair.app"
fi

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/Clawds-Lair-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged $ZIP"
fi
