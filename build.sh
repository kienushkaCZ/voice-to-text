#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="VoiceToText"
BUNDLE_ID="com.voicetotext.app"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

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
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice-to-Text needs microphone access to record your speech for transcription.</string>
</dict>
</plist>
PLIST

echo "==> App bundle created: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo "  # or: $MACOS_DIR/$APP_NAME"
echo ""
echo "To install to /Applications (optional):"
echo "  cp -R $APP_DIR /Applications/"
