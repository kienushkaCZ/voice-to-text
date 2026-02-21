import Foundation

enum Log {
    private static let logURL: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voice-to-text.log")
        // Clear log on launch
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    static func info(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("[VTT] %@", message)
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? line.write(to: logURL, atomically: false, encoding: .utf8)
        }
    }
}
