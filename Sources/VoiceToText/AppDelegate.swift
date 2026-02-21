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

    private var state: State = .idle
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private var deepgram: DeepgramClient?
    private let hud = HUD()

    // Key monitoring
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastToggleTime: TimeInterval = 0

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("App launched")
        // Clear any old notifications from previous versions
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        setupDeepgramClient()
        setupStatusItem()
        checkAccessibility()
        setupKeyMonitors()
        Log.info("Setup complete, ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    // MARK: - Setup

    private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        Log.info("Accessibility trusted: \(trusted)")
        if !trusted {
            Log.info("WARNING: Accessibility not granted")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    private func setupDeepgramClient() {
        let key = loadAPIKey()
        deepgram = DeepgramClient(apiKey: key)
        if deepgram == nil {
            Log.info("WARNING: DEEPGRAM_API_KEY not set")
        } else {
            Log.info("Deepgram client OK (key: \(key!.prefix(8))...)")
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
        guard deepgram != nil else {
            Log.info("ERROR: No Deepgram client")
            hud.show("API key not configured", icon: "\u{26A0}\u{FE0F}")
            return
        }

        do {
            try recorder.start()
            state = .recording
            updateIcon(for: .recording)
            NSSound(named: "Tink")?.play()
            hud.show("Recording...", icon: "\u{1F534}", duration: 60)
            Log.info("Recording STARTED")
        } catch {
            Log.info("Failed to start recording: \(error)")
            hud.show("Mic error: \(error.localizedDescription)", icon: "\u{274C}")
        }
    }

    private func stopRecordingAndTranscribe() {
        let pcmData = recorder.stop()
        state = .processing
        updateIcon(for: .processing)
        NSSound(named: "Pop")?.play()
        Log.info("Recording STOPPED, PCM: \(pcmData.count) bytes")

        guard !pcmData.isEmpty else {
            state = .idle
            updateIcon(for: .idle)
            Log.info("WARNING: Empty audio buffer")
            hud.show("No audio recorded", icon: "\u{274C}")
            return
        }

        hud.show("Recognizing...", icon: "\u{23F3}", duration: 30)

        let wavData = WavEncoder.encode(pcmData: pcmData)
        Log.info("WAV: \(wavData.count) bytes, sending to Deepgram...")

        Task {
            do {
                let transcript = try await deepgram!.transcribe(wavData: wavData)
                Log.info("Transcript: \"\(transcript)\"")
                await MainActor.run {
                    handleTranscription(transcript)
                }
            } catch {
                Log.info("Transcription error: \(error)")
                await MainActor.run {
                    state = .idle
                    updateIcon(for: .idle)
                    hud.show("Error: \(error.localizedDescription)", icon: "\u{274C}", duration: 5)
                }
            }
        }
    }

    private func handleTranscription(_ text: String) {
        state = .idle
        updateIcon(for: .idle)

        if text.isEmpty {
            hud.show("No speech detected", icon: "\u{274C}")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Log.info("Copied to clipboard: \"\(text)\"")
        hud.show(text, icon: "\u{2705}", duration: 4)
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

        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Voice-to-Text")?
            .withSymbolConfiguration(config)
    }

    // MARK: - Actions

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
