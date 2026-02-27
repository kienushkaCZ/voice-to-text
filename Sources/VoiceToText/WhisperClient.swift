import Foundation

final class WhisperClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutHandle: FileHandle?
    private var isReady = false
    private let lock = NSLock()

    /// Path to whisper_daemon.py (inside app bundle or config dir)
    private let daemonPath: String

    init?() {
        // Look for daemon script in these locations:
        // 1. App bundle Resources
        // 2. ~/.config/voice-to-text/whisper_daemon.py
        // 3. ~/voice-to-text/whisper_daemon.py
        let candidates = [
            Bundle.main.resourcePath.map { $0 + "/whisper_daemon.py" },
            NSString("~/.config/voice-to-text/whisper_daemon.py").expandingTildeInPath,
            NSString("~/voice-to-text/whisper_daemon.py").expandingTildeInPath,
        ].compactMap { $0 }

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            Log.info("WhisperClient: whisper_daemon.py not found")
            return nil
        }
        self.daemonPath = path
        Log.info("WhisperClient: daemon at \(path)")

        if !startDaemon() {
            return nil
        }
    }

    private func startDaemon() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", daemonPath]

        // Pass through WHISPER_MODEL env if set
        var env = ProcessInfo.processInfo.environment
        if env["WHISPER_MODEL"] == nil {
            // Read from config
            let configPath = NSString("~/.config/voice-to-text/config").expandingTildeInPath
            if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("WHISPER_MODEL=") {
                        env["WHISPER_MODEL"] = String(trimmed.dropFirst("WHISPER_MODEL=".count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    }
                }
            }
        }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Log stderr from daemon
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                Log.info("Whisper daemon: \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        do {
            try proc.run()
        } catch {
            Log.info("WhisperClient: failed to start daemon: \(error)")
            return false
        }

        self.process = proc
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stdoutHandle = outPipe.fileHandleForReading

        // Wait for READY signal (up to 30 seconds for model download)
        Log.info("WhisperClient: waiting for model to load...")
        guard let readyLine = readLine(timeout: 30), readyLine.contains("READY") else {
            Log.info("WhisperClient: daemon did not become ready")
            proc.terminate()
            return false
        }

        isReady = true
        Log.info("WhisperClient: ready")
        return true
    }

    func transcribe(wavData: Data) throws -> String {
        guard isReady, let process, process.isRunning else {
            throw WhisperError.notReady
        }

        // Write WAV to temp file
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try wavData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        lock.lock()
        defer { lock.unlock() }

        // Send path to daemon
        let pathLine = tmpURL.path + "\n"
        stdinPipe?.fileHandleForWriting.write(pathLine.data(using: .utf8)!)

        // Read transcript
        guard let result = readLine(timeout: 30) else {
            throw WhisperError.timeout
        }

        return result
    }

    private func readLine(timeout: TimeInterval) -> String? {
        guard let handle = stdoutHandle else { return nil }

        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            buffer.append(chunk)
            if let str = String(data: buffer, encoding: .utf8), str.contains("\n") {
                return str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    func shutdown() {
        stdinPipe?.fileHandleForWriting.closeFile()
        process?.terminate()
        process = nil
        isReady = false
    }

    deinit {
        shutdown()
    }

    enum WhisperError: Error, LocalizedError {
        case notReady
        case timeout

        var errorDescription: String? {
            switch self {
            case .notReady: return "Whisper daemon not ready"
            case .timeout: return "Whisper transcription timeout"
            }
        }
    }
}
