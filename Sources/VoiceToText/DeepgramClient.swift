import Foundation

final class DeepgramClient {
    private let apiKey: String
    private let session = URLSession.shared

    init?(apiKey: String?) {
        guard let key = apiKey, !key.isEmpty else { return nil }
        self.apiKey = key
    }

    func transcribe(wavData: Data) async throws -> String {
        let url = URL(string: "https://api.deepgram.com/v1/listen?model=nova-3&language=multi&smart_format=true")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DeepgramError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let result = try JSONDecoder().decode(DeepgramResponse.self, from: data)
        let transcript = result.results.channels.first?.alternatives.first?.transcript ?? ""
        return transcript
    }

    enum DeepgramError: Error, LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from Deepgram"
            case .apiError(let code, let message):
                return "Deepgram API error (\(code)): \(message)"
            }
        }
    }
}

// MARK: - Response model
private struct DeepgramResponse: Decodable {
    let results: Results

    struct Results: Decodable {
        let channels: [Channel]
    }

    struct Channel: Decodable {
        let alternatives: [Alternative]
    }

    struct Alternative: Decodable {
        let transcript: String
    }
}
