#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="VoiceToText"
BUNDLE_ID="com.voicetotext.app"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INSTALLED_APP="/Applications/$APP_NAME.app"

echo "==> Building $APP_NAME (release)..."
swift build -c release 2>&1

BINARY=$(swift build -c release --show-bin-path)/$APP_NAME

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BINARY" "$MACOS_DIR/$APP_NAME"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
mkdir -p "$RESOURCES_DIR"
cp "$SCRIPT_DIR/whisper_daemon.py" "$RESOURCES_DIR/whisper_daemon.py"
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.voicetotext.app</string>
    <key>CFBundleName</key>
    <string>VoiceToText</string>
    <key>CFBundleDisplayName</key>
    <string>Voice-to-Text</string>
    <key>CFBundleExecutable</key>
    <string>VoiceToText</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice-to-Text needs microphone access to record your speech for transcription.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"
echo "==> App bundle created: $APP_DIR"

# Install to /Applications (kill running app, replace, relaunch)
if [ "${1:-}" = "--install" ] || [ "${1:-}" = "-i" ]; then
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_DIR" "$INSTALLED_APP"
    echo "==> Installed to $INSTALLED_APP"
    echo ""
    echo "IMPORTANT: After install, check Accessibility permission:"
    echo "  System Settings > Privacy & Security > Accessibility"
    echo "  Remove old VoiceToText, add $INSTALLED_APP, enable toggle."
    echo ""
    open "$INSTALLED_APP"
    echo "==> Launched $APP_NAME"
else
    # Just update the binary in-place (preserves Accessibility permission)
    if [ -d "$INSTALLED_APP" ]; then
        pkill -9 -x "$APP_NAME" 2>/dev/null || true
        sleep 1
        cp "$MACOS_DIR/$APP_NAME" "$INSTALLED_APP/Contents/MacOS/$APP_NAME"
        cp "$RESOURCES_DIR/whisper_daemon.py" "$INSTALLED_APP/Contents/Resources/whisper_daemon.py"
        if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
            cp "$RESOURCES_DIR/AppIcon.icns" "$INSTALLED_APP/Contents/Resources/AppIcon.icns"
        fi
        cp "$CONTENTS_DIR/Info.plist" "$INSTALLED_APP/Contents/Info.plist"
        codesign --force --sign - "$INSTALLED_APP"
        echo "==> Updated $INSTALLED_APP (in-place, permissions preserved)"
        open "$INSTALLED_APP"
        echo "==> Relaunched $APP_NAME"
    else
        echo ""
        echo "First time? Run: bash build.sh --install"
    fi
fi
