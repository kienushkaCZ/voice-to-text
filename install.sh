#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="VoiceToText"
APP_PATH="$SCRIPT_DIR/$APP_NAME.app"
PLIST_PATH="$HOME/Library/LaunchAgents/com.voicetotext.app.plist"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found. Run build.sh first."
    exit 1
fi

echo "==> Installing LaunchAgent for auto-start..."

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.voicetotext.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>open</string>
        <string>$APP_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> LaunchAgent installed: $PLIST_PATH"
echo ""
echo "The app will start automatically on login."
echo "To start it now: open $APP_PATH"
echo ""
echo "To uninstall:"
echo "  launchctl unload $PLIST_PATH"
echo "  rm $PLIST_PATH"
