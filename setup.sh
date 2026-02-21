#!/bin/bash
set -euo pipefail

# Voice-to-Text — one-command setup for a new Mac
# Usage: curl -sL <url> | bash   OR   bash setup.sh

INSTALL_DIR="$HOME/voice-to-text"
CONFIG_DIR="$HOME/.config/voice-to-text"

echo "==> Voice-to-Text Setup"
echo ""

# 1. Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "ERROR: Xcode Command Line Tools required."
    echo "Run: xcode-select --install"
    exit 1
fi

# 2. Check for swift
if ! command -v swift &>/dev/null; then
    echo "ERROR: Swift not found. Install Xcode Command Line Tools."
    exit 1
fi

# 3. API key
if [ -f "$CONFIG_DIR/config" ] && grep -q "DEEPGRAM_API_KEY=" "$CONFIG_DIR/config" 2>/dev/null; then
    echo "==> API key already configured"
else
    echo -n "Enter your Deepgram API key: "
    read -r API_KEY
    if [ -z "$API_KEY" ]; then
        echo "ERROR: API key is required"
        exit 1
    fi
    mkdir -p "$CONFIG_DIR"
    echo "DEEPGRAM_API_KEY=$API_KEY" > "$CONFIG_DIR/config"
    echo "==> API key saved to $CONFIG_DIR/config"
fi

# 4. Build
echo "==> Building (this may take a minute on first run)..."
cd "$INSTALL_DIR"
bash build.sh

# 5. Install LaunchAgent
bash install.sh

# 6. Add aliases to .zshrc
if ! grep -q "vtt-restart" "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" << 'ALIASES'

# Voice-to-Text aliases
alias vtt-restart='pkill -x VoiceToText; sleep 1; open ~/voice-to-text/VoiceToText.app && echo "VoiceToText restarted"'
alias vtt-stop='pkill -x VoiceToText && echo "VoiceToText stopped"'
alias vtt-log='tail -20 ~/.voice-to-text.log'
ALIASES
    echo "==> Aliases added to .zshrc (vtt-restart, vtt-stop, vtt-log)"
fi

# 7. Launch
echo "==> Launching..."
open "$INSTALL_DIR/VoiceToText.app"

echo ""
echo "========================================="
echo "  Voice-to-Text installed!"
echo "========================================="
echo ""
echo "IMPORTANT — grant permissions:"
echo "  1. System Settings → Privacy & Security → Accessibility"
echo "     → add VoiceToText.app"
echo "  2. Microphone — allow when prompted"
echo ""
echo "Usage:"
echo "  Right CMD → start recording"
echo "  Right CMD → stop & transcribe"
echo "  Cmd+V     → paste result"
echo ""
echo "Commands:"
echo "  vtt-restart  — restart the app"
echo "  vtt-stop     — stop the app"
echo "  vtt-log      — view logs"
echo ""
