import Foundation

enum WavEncoder {
    /// Encode raw PCM data (16-bit Int, mono) into a WAV file.
    static func encode(pcmData: Data, sampleRate: UInt32 = 16000, channels: UInt16 = 1, bitsPerSample: UInt16 = 16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var header = Data(capacity: 44)

        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(littleEndian: chunkSize)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt sub-chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(littleEndian: UInt32(16))               // Sub-chunk size
        header.append(littleEndian: UInt16(1))                // PCM format
        header.append(littleEndian: channels)
        header.append(littleEndian: sampleRate)
        header.append(littleEndian: byteRate)
        header.append(littleEndian: blockAlign)
        header.append(littleEndian: bitsPerSample)

        // data sub-chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(littleEndian: dataSize)

        return header + pcmData
    }
}

// MARK: - Data helpers for little-endian encoding
private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
