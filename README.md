# Voice-to-Text

Native macOS menu bar app for voice input. Press **Right CMD** to record your speech, press again to stop — transcribed text is instantly copied to your clipboard, ready to paste anywhere.

Built with Swift. Uses [Deepgram](https://deepgram.com/) nova-3 for fast, accurate speech recognition.

## Features

- **One-key workflow** — Right CMD to start/stop, Cmd+V to paste
- **Multi-language** — English, Russian, Spanish, French, German, Portuguese, Japanese, Italian, Dutch, Hindi (mixed in one sentence)
- **Lives in menu bar** — no Dock icon, no windows, stays out of your way
- **Visual feedback** — floating HUD shows recording status and transcription result
- **Auto-start** — launches on login, always ready
- **Fast** — typically 1-2 seconds from stop to clipboard

## Quick Install

> Requires macOS 13+ and Xcode Command Line Tools.

**1. Install Xcode Command Line Tools** (if you don't have them):

```bash
xcode-select --install
```

**2. Get a Deepgram API key:**

You need a free API key from Deepgram (speech recognition service).

1. Go to [console.deepgram.com](https://console.deepgram.com/) and sign up (Google/GitHub or email)
2. After sign-up you'll land on the Dashboard. Deepgram gives **$200 in free credits** — this is enough for ~500 hours of transcription
3. In the left sidebar, click **API Keys**
4. Click **Create a New API Key**
5. Give it a name (e.g. "voice-to-text"), set **Role** to "Member", **Expiration** to "Never"
6. Click **Create Key** and **copy the key** — you'll need it in the next step

> **Important:** The key is shown only once. If you lose it, just create a new one.

**3. Clone and install:**

```bash
git clone https://github.com/kienushkaCZ/voice-to-text.git ~/voice-to-text
cd ~/voice-to-text
bash setup.sh
```

The setup script will ask for your API key, build the app, set up auto-start, and launch it.

**4. Grant permissions** (one-time, manual):

| Permission | How to enable |
|------------|--------------|
| **Accessibility** | System Settings → Privacy & Security → Accessibility → click **+** → navigate to `~/voice-to-text/VoiceToText.app` → toggle ON |
| **Microphone** | Automatically prompted on first recording — click Allow |

> **Tip:** To navigate to the app in Finder's file picker, press **Cmd+Shift+G** and type `~/voice-to-text/`

## How It Works

```
Right CMD        Right CMD          ~1-2 sec
    |                |                 |
    v                v                 v
 [Idle] ──► [Recording] ──► [Recognizing...] ──► [Copied!]
   🎙            🔴               ⏳                ✅
                                                     |
                                              Cmd+V to paste
```

1. Press **Right CMD** — mic icon turns red, recording starts
2. Speak (any length)
3. Press **Right CMD** again — recording stops, audio is sent to Deepgram
4. Transcribed text appears in a floating HUD and is copied to clipboard
5. **Cmd+V** to paste anywhere

## Terminal Commands

After installation, these aliases are available in your terminal:

```bash
vtt-restart    # Kill and relaunch the app
vtt-stop       # Stop the app
vtt-log        # Show recent logs (useful for debugging)
```

## Troubleshooting

### App doesn't react to Right CMD
- **Check Accessibility permission:** System Settings → Privacy & Security → Accessibility → make sure VoiceToText is listed and toggled ON
- After rebuilding the app, macOS resets the permission — you need to remove and re-add VoiceToText.app in Accessibility settings
- Run `vtt-log` to check if key events are being captured

### "No audio recorded" error
- **Check Microphone permission:** System Settings → Privacy & Security → Microphone → make sure VoiceToText is allowed
- Run `vtt-log` — look for the mic format line to confirm the mic is accessible

### App doesn't appear in menu bar
- The idle mic icon can blend in with the menu bar. Look carefully near the right side of the menu bar
- Try `vtt-restart` to relaunch

### Transcription returns empty or wrong language
- Check your API key: `cat ~/.config/voice-to-text/config`
- Run `vtt-log` to see the API response
- The app uses `language=multi` mode which supports 10 languages. Czech, Polish, and some others are not yet supported by Deepgram

### How to completely uninstall

```bash
vtt-stop
launchctl unload ~/Library/LaunchAgents/com.voicetotext.app.plist
rm ~/Library/LaunchAgents/com.voicetotext.app.plist
rm -rf ~/voice-to-text
rm ~/.config/voice-to-text/config
rm ~/.voice-to-text.log
# Remove aliases from ~/.zshrc manually
```

## Configuration

API key is stored locally (never committed to git):

```
~/.config/voice-to-text/config
```

```
DEEPGRAM_API_KEY=your-key-here
```

## Supported Languages

Deepgram nova-3 multi-language mode supports mixing these languages in one recording:

| Language | Language | Language |
|----------|----------|----------|
| English | French | Japanese |
| Russian | German | Italian |
| Spanish | Portuguese | Dutch |
| Hindi | | |

Additional languages available in monolingual mode — see [Deepgram docs](https://developers.deepgram.com/docs/models-languages-overview).

## Tech Stack

- **Language:** Swift
- **Build:** Swift Package Manager
- **Audio:** AVAudioEngine (16kHz, mono, PCM16)
- **API:** Deepgram REST API (nova-3)
- **UI:** NSStatusItem (menu bar) + custom floating HUD

## License

MIT
