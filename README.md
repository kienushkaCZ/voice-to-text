# Voice-to-Text

macOS menu bar app for voice input. Press **Right CMD** to record, press again to stop — transcribed text is copied to clipboard.

Uses [Deepgram](https://deepgram.com/) nova-3 for speech recognition with multi-language support (English, Russian, Spanish, French, German, and more).

## Quick Install

```bash
git clone https://github.com/kienushkaCZ/voice-to-text.git ~/voice-to-text
cd ~/voice-to-text
bash setup.sh
```

The setup script will:
- Build the app
- Ask for your Deepgram API key
- Set up auto-start on login
- Add terminal aliases

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- [Deepgram API key](https://console.deepgram.com/) (free tier available)

## Permissions (grant manually after install)

1. **Accessibility** — System Settings → Privacy & Security → Accessibility → add VoiceToText.app
2. **Microphone** — allow when prompted on first use

## Usage

| Action | What happens |
|--------|-------------|
| **Right CMD** | Start recording (red mic icon) |
| **Right CMD** again | Stop & transcribe (hourglass icon) |
| **Cmd+V** | Paste transcribed text |

## Terminal Commands

```bash
vtt-restart   # Restart the app
vtt-stop      # Stop the app
vtt-log       # View recent logs
```

## Config

API key is stored in `~/.config/voice-to-text/config`:

```
DEEPGRAM_API_KEY=your-key-here
```
