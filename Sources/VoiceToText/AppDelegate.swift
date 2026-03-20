import Cocoa
import AVFoundation
import UserNotifications

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
    private var autoPaste: Bool = false
    private let hud = HUD()

    // Key monitoring
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastToggleTime: TimeInterval = 0

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("App launched")
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        loadEngine()
        setupStatusItem()
        checkAccessibility()
        setupKeyMonitors()
        Log.info("Setup complete, engine=\(engine), ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        whisper?.shutdown()
    }

    // MARK: - Setup

    private func loadEngine() {
        // Read ENGINE from config (default: whisper)
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
                if trimmed.hasPrefix("AUTO_PASTE=") {
                    let value = String(trimmed.dropFirst("AUTO_PASTE=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                        .lowercased()
                    autoPaste = (value == "true" || value == "1" || value == "yes")
                }
            }
        }

        Log.info("Engine: \(engine), autoPaste: \(autoPaste)")

        switch engine {
        case .whisper:
            hud.show("Loading Whisper...", icon: "🧠", duration: 30)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let client = WhisperClient()
                DispatchQueue.main.async {
                    self?.whisper = client
                    if client != nil {
                        self?.hud.show("Whisper ready", icon: "✅", duration: 2)
                        Log.info("Whisper client ready")
                    } else {
                        // Fallback to Deepgram
                        Log.info("Whisper failed, falling back to Deepgram")
                        self?.engine = .deepgram
                        self?.setupDeepgramClient()
                        self?.hud.show("Whisper unavailable, using Deepgram", icon: "☁️", duration: 3)
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
            hud.show("API key required — click menu bar icon", icon: "⚠️", duration: 5)
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

        // Ensure ENGINE=deepgram is set
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

        let autoPasteItem = NSMenuItem(title: "Auto-Paste", action: #selector(toggleAutoPaste(_:)), keyEquivalent: "")
        autoPasteItem.state = autoPaste ? .on : .off
        menu.addItem(autoPasteItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit Voice-to-Text", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupKeyMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: "global")
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: "local")
            return event
        }
        Log.info("Key monitors installed")
    }

    // MARK: - Key handling

    private func handleFlagsChanged(_ event: NSEvent, source: String) {
        guard event.keyCode == 54, event.modifierFlags.contains(.command) else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastToggleTime > 0.5 else {
            Log.info("Debounced (\(source)) — skipping")
            return
        }
        lastToggleTime = now

        Log.info("Right CMD pressed (\(source)), state=\(state)")
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecording()
        }
    }

    // MARK: - State machine

    private func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .processing:
            Log.info("Ignoring — still processing")
        }
    }

    private func startRecording() {
        // Check that at least one engine is available
        guard deepgram != nil || whisper != nil else {
            Log.info("ERROR: No transcription engine available")
            hud.show("No engine available", icon: "⚠️")
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
            hud.showRecording("Recording...", icon: "🔴")
            Log.info("Recording STARTED")
        } catch {
            Log.info("Failed to start recording: \(error)")
            hud.show("Mic error: \(error.localizedDescription)", icon: "❌")
        }
    }

    private func stopRecordingAndTranscribe() {
        recorder.onLevel = nil
        let pcmData = recorder.stop()
        state = .processing
        updateIcon(for: .processing)
        NSSound(named: "Pop")?.play()
        Log.info("Recording STOPPED, PCM: \(pcmData.count) bytes")

        guard !pcmData.isEmpty else {
            state = .idle
            updateIcon(for: .idle)
            Log.info("WARNING: Empty audio buffer")
            hud.show("No audio recorded", icon: "❌")
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
        hud.showWithProgress("Recognizing (\(engineLabel))...", icon: "⏳", estimatedDuration: estimatedTime)

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
                    state = .idle
                    updateIcon(for: .idle)
                    hud.show("Error: \(error.localizedDescription)", icon: "❌", duration: 5)
                }
            }
        }
    }

    private func handleTranscription(_ text: String) {
        state = .idle
        updateIcon(for: .idle)

        if text.isEmpty {
            NSSound(named: "Basso")?.play()
            hud.show("No speech detected", icon: "❌")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        NSSound(named: "Purr")?.play()
        Log.info("Copied to clipboard: \"\(text)\"")

        if autoPaste {
            // Dispatch paste on a background thread to avoid blocking main thread with usleep
            DispatchQueue.global(qos: .userInteractive).async {
                self.simulatePaste()
            }
            // Show HUD after paste so it doesn't interfere with focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.hud.show(text, icon: "✅", duration: 2)
            }
        } else {
            hud.show(text, icon: "✅", duration: 4)
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

    // MARK: - UI

    private func updateIcon(for state: State) {
        guard let button = statusItem.button else { return }

        let config: NSImage.SymbolConfiguration
        let imageName: String

        switch state {
        case .idle:
            imageName = autoPaste ? "mic.circle.fill" : "mic"
            config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        case .recording:
            imageName = autoPaste ? "mic.circle.fill" : "mic.fill"
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

    // MARK: - Actions

    @objc private func toggleAutoPaste(_ sender: NSMenuItem) {
        autoPaste.toggle()
        sender.state = autoPaste ? .on : .off
        Log.info("Auto-paste: \(autoPaste), state=\(state)")
        updateIcon(for: state)
        saveAutoPasteToConfig()
    }

    private func saveAutoPasteToConfig() {
        let configPath = NSString("~/.config/voice-to-text/config").expandingTildeInPath
        var lines: [String] = []
        if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines)
        }

        // Update or add AUTO_PASTE line
        var found = false
        for i in lines.indices {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("AUTO_PASTE=") {
                lines[i] = "AUTO_PASTE=\(autoPaste)"
                found = true
                break
            }
        }
        if !found {
            lines.append("AUTO_PASTE=\(autoPaste)")
        }

        // Remove trailing empty lines, then ensure final newline
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
