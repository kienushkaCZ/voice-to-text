import Cocoa
import AVFoundation
import UserNotifications

// MARK: - History Entry

struct HistoryEntry: Codable {
    let date: Date
    let text: String
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private enum State: CustomStringConvertible {
        case idle, recording, processing
        var description: String {
            switch self {
            case .idle: return "idle"
            case .recording: return "recording"
            case .processing: return "processing"
            }
        }
    }

    private enum Engine: String {
        case whisper
        case deepgram
    }

    private var state: State = .idle
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private var deepgram: DeepgramClient?
    private var whisper: WhisperClient?
    private var engine: Engine = .whisper
    private let hud = HUD()

    // Key monitoring
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var lastToggleTime: TimeInterval = 0

    // Right Command key logic
    private var cmdPressTime: TimeInterval = 0
    private var pttDelayTask: DispatchWorkItem?
    private var isPTTActive: Bool = false
    private var isHandsFree: Bool = false

    // Safety timeout
    private var stateTimeoutTask: DispatchWorkItem?

    // Transcription history
    private var history: [HistoryEntry] = []
    private var historyMenu: NSMenu?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("App launched")
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        loadEngine()
        loadHistory()
        setupStatusItem()
        checkAccessibility()
        setupKeyMonitors()
        Log.info("Setup complete, engine=\(engine), Right Cmd hold=PTT, Right Cmd tap=Toggle, ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeKeyMonitors()
        whisper?.shutdown()
    }

    // MARK: - Setup

    private func loadEngine() {
        let configPath = NSString("~/.config/voice-to-text/config").expandingTildeInPath
        if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ENGINE=") {
                    let value = String(trimmed.dropFirst("ENGINE=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                        .lowercased()
                    if let e = Engine(rawValue: value) {
                        engine = e
                    }
                }
            }
        }

        Log.info("Engine: \(engine)")

        switch engine {
        case .whisper:
            hud.show("Loading Whisper...", icon: "\u{1F9E0}", duration: 30)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let client = WhisperClient()
                DispatchQueue.main.async {
                    self?.whisper = client
                    if client != nil {
                        self?.hud.show("Whisper ready", icon: "\u{2705}", duration: 2)
                        Log.info("Whisper client ready")
                    } else {
                        Log.info("Whisper failed, falling back to Deepgram")
                        self?.engine = .deepgram
                        self?.setupDeepgramClient()
                        self?.hud.show("Whisper unavailable, using Deepgram", icon: "\u{2601}\u{FE0F}", duration: 3)
                    }
                }
            }
        case .deepgram:
            setupDeepgramClient()
        }
    }

    private func setupDeepgramClient() {
        var key = loadAPIKey()
        if key == nil {
            key = promptForAPIKey()
        }
        deepgram = DeepgramClient(apiKey: key)
        if deepgram == nil {
            Log.info("WARNING: DEEPGRAM_API_KEY not set")
            hud.show("API key required \u{2014} click menu bar icon", icon: "\u{26A0}\u{FE0F}", duration: 5)
        } else {
            Log.info("Deepgram client OK (key: \(key!.prefix(8))...)")
        }
    }

    private func promptForAPIKey() -> String? {
        let alert = NSAlert()
        alert.messageText = "Deepgram API Key"
        alert.informativeText = "Enter your Deepgram API key.\nGet one free at console.deepgram.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        input.placeholderString = "paste your API key here"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        // Save to config
        let configDir = NSString("~/.config/voice-to-text").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let configPath = configDir + "/config"

        var lines: [String] = []
        if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines)
        }

        var found = false
        for i in lines.indices {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("DEEPGRAM_API_KEY=") {
                lines[i] = "DEEPGRAM_API_KEY=\(key)"
                found = true
                break
            }
        }
        if !found {
            lines.append("DEEPGRAM_API_KEY=\(key)")
        }

        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("ENGINE=") }) {
            lines.append("ENGINE=deepgram")
        }

        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(toFile: configPath, atomically: true, encoding: .utf8)
        Log.info("API key saved to config")

        return key
    }

    private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        Log.info("Accessibility trusted: \(trusted)")
        if !trusted {
            Log.info("WARNING: Accessibility not granted")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    private func loadAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        let configPath = NSString("~/.config/voice-to-text/config").expandingTildeInPath
        if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("DEEPGRAM_API_KEY=") {
                    let value = String(trimmed.dropFirst("DEEPGRAM_API_KEY=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)

        let menu = NSMenu()

        // Engine indicator
        let engineItem = NSMenuItem(title: "Engine: \(engine.rawValue)", action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)

        menu.addItem(NSMenuItem.separator())

        // Hardcoded hotkey info (disabled, informational)
        let fnItem = NSMenuItem(title: "Right \u{2318} hold: Push-to-Talk", action: nil, keyEquivalent: "")
        fnItem.isEnabled = false
        menu.addItem(fnItem)

        let fnSpaceItem = NSMenuItem(title: "Right \u{2318} tap: Hands-Free Toggle", action: nil, keyEquivalent: "")
        fnSpaceItem.isEnabled = false
        menu.addItem(fnSpaceItem)

        menu.addItem(NSMenuItem.separator())

        // History submenu
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let histSubmenu = NSMenu()
        historyItem.submenu = histSubmenu
        self.historyMenu = histSubmenu
        menu.addItem(historyItem)
        updateHistoryMenu()

        menu.addItem(NSMenuItem.separator())

        // Help submenu
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpSubmenu = NSMenu()

        let helpLines: [(String, Bool)] = [
            ("Hotkeys:", false),
            ("  Hold Right \u{2318} \u{2014} Push-to-Talk", false),
            ("    (hold, speak, release \u{2192} auto-paste)", false),
            ("  Tap Right \u{2318} \u{2014} Hands-Free Toggle", false),
            ("    (tap to start, tap to stop \u{2192} auto-paste)", false),
            ("", false),
            ("Terminal commands:", false),
            ("  Restart: pkill VoiceToText && open -a VoiceToText", false),
            ("  Logs: tail -f ~/.voice-to-text.log", false),
            ("  Config: ~/.config/voice-to-text/config", false),
        ]
        for (text, enabled) in helpLines {
            if text.isEmpty {
                helpSubmenu.addItem(NSMenuItem.separator())
            } else {
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.isEnabled = enabled
                helpSubmenu.addItem(item)
            }
        }

        helpItem.submenu = helpSubmenu
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit Voice-to-Text", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func removeKeyMonitors() {
        if let m = globalFlagsMonitor   { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor    { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
        if let m = globalKeyDownMonitor { NSEvent.removeMonitor(m); globalKeyDownMonitor = nil }
        if let m = localKeyDownMonitor  { NSEvent.removeMonitor(m); localKeyDownMonitor = nil }
    }

    private func setupKeyMonitors() {
        removeKeyMonitors()

        // flagsChanged monitors (detect Fn press/release)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: "global")
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: "local")
            return event
        }

        // keyDown monitors (detect Space while Fn is held)
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event, source: "global")
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event, source: "local")
            return event
        }

        Log.info("Installed key monitors (flagsChanged, keyDown)")
    }

    // MARK: - Key handling

    private func handleFlagsChanged(_ event: NSEvent, source: String) {
        // Only interested in Right Command (keyCode 54)
        guard event.keyCode == 54 else { return }

        let cmdDown = event.modifierFlags.contains(.command)

        if cmdDown {
            // Right Command pressed down
            let now = ProcessInfo.processInfo.systemUptime
            cmdPressTime = now

            // If we're in hands-free recording, a press means stop
            if isHandsFree && state == .recording {
                Log.info("Hands-free stop (Right Cmd) (\(source)), state=\(state)")
                isHandsFree = false
                NSSound(named: "Submarine")?.play()
                stopRecordingAndTranscribe()
                return
            }

            // Schedule PTT start after 0.3s
            // If released before that, it's a quick tap → toggle hands-free
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.state == .idle else { return }
                Log.info("PTT start (Right Cmd held) (\(source)), state=\(self.state)")
                self.isPTTActive = true
                self.startRecording()
            }
            pttDelayTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        } else {
            // Right Command released
            let now = ProcessInfo.processInfo.systemUptime
            let holdDuration = now - cmdPressTime

            pttDelayTask?.cancel()
            pttDelayTask = nil

            if isPTTActive && state == .recording {
                // PTT release → stop recording
                Log.info("PTT stop (Right Cmd released, held \(String(format: "%.2f", holdDuration))s) (\(source))")
                isPTTActive = false
                stopRecordingAndTranscribe()
            } else if !isPTTActive && state == .idle && holdDuration < 0.3 {
                // Quick tap → toggle hands-free on
                Log.info("Hands-free start (Right Cmd tap) (\(source))")
                isHandsFree = true
                startRecording()
            }

            isPTTActive = false
            cmdPressTime = 0
        }
    }

    private func handleKeyDown(_ event: NSEvent, source: String) {
        // Currently unused — all logic is via Left Control flagsChanged
    }

    // MARK: - State machine

    private func startRecording() {
        guard state == .idle else {
            Log.info("Cannot start recording, state=\(state)")
            return
        }

        // Check that at least one engine is available
        guard deepgram != nil || whisper != nil else {
            Log.info("ERROR: No transcription engine available")
            hud.show("No engine available", icon: "\u{26A0}\u{FE0F}")
            return
        }

        do {
            recorder.onLevel = { [weak self] level in
                self?.hud.updateAudioLevel(level)
            }
            try recorder.start()
            state = .recording
            updateIcon(for: .recording)
            NSSound(named: "Tink")?.play()
            hud.showRecording("Recording...", icon: "\u{1F534}")
            scheduleStateTimeout(for: .recording, seconds: 900)
            Log.info("Recording STARTED")
        } catch {
            Log.info("Failed to start recording: \(error)")
            hud.show("Mic error: \(error.localizedDescription)", icon: "\u{274C}")
        }
    }

    private func stopRecordingAndTranscribe() {
        cancelStateTimeout()
        recorder.onLevel = nil
        let pcmData = recorder.stop()
        state = .processing
        updateIcon(for: .processing)
        NSSound(named: "Pop")?.play()
        scheduleStateTimeout(for: .processing, seconds: 30)
        Log.info("Recording STOPPED, PCM: \(pcmData.count) bytes")

        guard !pcmData.isEmpty else {
            state = .idle
            updateIcon(for: .idle)
            Log.info("WARNING: Empty audio buffer")
            hud.show("No audio recorded", icon: "\u{274C}")
            return
        }

        let engineLabel = engine == .whisper ? "Whisper" : "Deepgram"

        // Estimate processing time from audio duration
        // PCM: 16kHz, 16-bit mono = 32000 bytes/sec
        let audioSeconds = Double(pcmData.count) / 32000.0
        let estimatedTime: TimeInterval
        switch engine {
        case .deepgram:
            estimatedTime = max(audioSeconds / 8.0 + 2.0, 3.0)
        case .whisper:
            estimatedTime = max(audioSeconds / 2.0 + 1.0, 3.0)
        }
        hud.showWithProgress("Recognizing (\(engineLabel))...", icon: "\u{23F3}", estimatedDuration: estimatedTime)

        let wavData = WavEncoder.encode(pcmData: pcmData)
        Log.info("WAV: \(wavData.count) bytes, sending to \(engineLabel)...")

        Task {
            do {
                let transcript: String
                switch engine {
                case .whisper:
                    transcript = try whisper!.transcribe(wavData: wavData)
                case .deepgram:
                    transcript = try await deepgram!.transcribe(wavData: wavData)
                }
                Log.info("Transcript: \"\(transcript)\"")
                await MainActor.run {
                    handleTranscription(transcript)
                }
            } catch {
                Log.info("Transcription error: \(error)")
                await MainActor.run {
                    cancelStateTimeout()
                    state = .idle
                    updateIcon(for: .idle)
                    hud.show("Error: \(error.localizedDescription)", icon: "\u{274C}", duration: 5)
                }
            }
        }
    }

    private func handleTranscription(_ text: String) {
        cancelStateTimeout()
        state = .idle
        updateIcon(for: .idle)

        if text.isEmpty {
            NSSound(named: "Basso")?.play()
            hud.show("No speech detected", icon: "\u{274C}")
            return
        }

        // Always copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        NSSound(named: "Purr")?.play()
        Log.info("Copied to clipboard: \"\(text)\"")

        // Add to history
        addToHistory(text)

        // Always auto-paste
        DispatchQueue.global(qos: .userInteractive).async {
            self.simulatePaste()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hud.show(text, icon: "\u{2705}", duration: 2)
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            Log.info("WARNING: Failed to create CGEvent for paste")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp.post(tap: .cghidEventTap)
        Log.info("Auto-pasted via Cmd+V")
    }

    // MARK: - Safety timeout

    private func scheduleStateTimeout(for expectedState: State, seconds: TimeInterval) {
        stateTimeoutTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.state == expectedState else { return }
            Log.info("Safety timeout: stuck in \(expectedState) for \(Int(seconds))s, resetting to idle")
            if expectedState == .recording {
                self.recorder.onLevel = nil
                _ = self.recorder.stop()
                self.isPTTActive = false
                self.isHandsFree = false
            }
            self.state = .idle
            self.updateIcon(for: .idle)
            self.hud.show("Reset (timeout)", icon: "⏱", duration: 2)
        }
        stateTimeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    private func cancelStateTimeout() {
        stateTimeoutTask?.cancel()
        stateTimeoutTask = nil
    }

    // MARK: - UI

    private func updateIcon(for state: State) {
        guard let button = statusItem.button else { return }

        let config: NSImage.SymbolConfiguration
        let imageName: String

        switch state {
        case .idle:
            imageName = "mic"
            config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        case .recording:
            imageName = "mic.fill"
            config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        case .processing:
            imageName = "ellipsis.circle"
            config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        }

        let img = NSImage(systemSymbolName: imageName, accessibilityDescription: "Voice-to-Text")?
            .withSymbolConfiguration(config)
        button.image = img
        Log.info("Icon updated: \(imageName), image=\(img != nil ? "OK" : "NIL")")
    }

    // MARK: - History

    private var historyFilePath: String {
        NSString("~/.config/voice-to-text/history.json").expandingTildeInPath
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: historyFilePath)) else {
            Log.info("No history file found, starting fresh")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            history = try decoder.decode([HistoryEntry].self, from: data)
            Log.info("Loaded \(history.count) history entries")
        } catch {
            Log.info("Failed to decode history: \(error)")
        }
    }

    private func saveHistory() {
        let configDir = NSString("~/.config/voice-to-text").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(history)
            try data.write(to: URL(fileURLWithPath: historyFilePath))
            Log.info("Saved \(history.count) history entries")
        } catch {
            Log.info("Failed to save history: \(error)")
        }
    }

    private func addToHistory(_ text: String) {
        let entry = HistoryEntry(date: Date(), text: text)
        history.insert(entry, at: 0)
        if history.count > 10 {
            history = Array(history.prefix(10))
        }
        saveHistory()
        updateHistoryMenu()
    }

    private func updateHistoryMenu() {
        guard let menu = historyMenu else { return }
        menu.removeAllItems()

        if history.isEmpty {
            let emptyItem = NSMenuItem(title: "No history", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for (index, entry) in history.enumerated() {
            let timeStr = timeFormatter.string(from: entry.date)
            let truncated: String
            if entry.text.count > 60 {
                truncated = String(entry.text.prefix(60)) + "..."
            } else {
                truncated = entry.text
            }
            let title = "\(timeStr) \u{2014} \(truncated)"
            let item = NSMenuItem(title: title, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = entry.text
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        hud.show("Copied to clipboard", icon: "\u{2705}", duration: 2)
        Log.info("Copied history item to clipboard: \"\(text.prefix(60))...\"")
    }

    @objc private func clearHistory() {
        history.removeAll()
        saveHistory()
        updateHistoryMenu()
        Log.info("History cleared")
    }

    // MARK: - Actions

    @objc private func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
