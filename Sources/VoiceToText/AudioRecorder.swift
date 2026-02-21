import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var rawData = Data()
    private var inputFormat: AVAudioFormat?
    private let lock = NSLock()

    var isRecording: Bool { engine.isRunning }

    func start() throws {
        rawData = Data()

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        inputFormat = nativeFormat
        Log.info("Mic format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch, \(nativeFormat.commonFormat.rawValue)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self, let floatData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            // Copy float samples immediately (buffer gets reused)
            let bytes = Data(bytes: floatData[0], count: frameCount * MemoryLayout<Float>.size)
            self.lock.lock()
            self.rawData.append(bytes)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let captured = rawData
        rawData = Data()
        lock.unlock()

        guard !captured.isEmpty, let srcFormat = inputFormat else {
            Log.info("No audio data captured")
            return Data()
        }

        let srcSampleRate = srcFormat.sampleRate
        let floatSampleCount = captured.count / MemoryLayout<Float>.size
        Log.info("Captured \(floatSampleCount) float samples (\(Double(floatSampleCount) / srcSampleRate)s at \(srcSampleRate)Hz)")

        // Convert: Float32 @ srcSampleRate → Int16 @ 16kHz mono
        let targetSampleRate = 16000.0
        let ratio = targetSampleRate / srcSampleRate

        // Read float samples
        let floatSamples = captured.withUnsafeBytes { ptr -> [Float] in
            let buf = ptr.bindMemory(to: Float.self)
            return Array(buf)
        }

        // Resample using linear interpolation
        let outputCount = Int(Double(floatSamples.count) * ratio)
        var int16Data = Data(capacity: outputCount * 2)

        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let idx0 = Int(srcIndex)
            let frac = Float(srcIndex - Double(idx0))
            let idx1 = min(idx0 + 1, floatSamples.count - 1)

            let sample = floatSamples[idx0] * (1.0 - frac) + floatSamples[idx1] * frac

            // Clamp and convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            var int16 = Int16(clamped * 32767.0)
            withUnsafeBytes(of: &int16) { int16Data.append(contentsOf: $0) }
        }

        Log.info("Converted to \(int16Data.count) bytes PCM16 (\(Double(outputCount) / targetSampleRate)s at 16kHz)")
        return int16Data
    }
}
