import Foundation

/// HTTP client for MiniMax API endpoints.
public final class MiniMaxAPIClient {
    public static let shared = MiniMaxAPIClient()

    private let session: URLSession
    private var provider: MiniMaxProvider { MiniMaxProvider.shared }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Common

    private func makeRequest(path: String, body: [String: Any]) throws -> URLRequest {
        guard provider.isConfigured else {
            throw MiniMaxError.notConfigured
        }
        guard let url = URL(string: provider.baseURL + path) else {
            throw MiniMaxError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func makeGetRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard provider.isConfigured else {
            throw MiniMaxError.notConfigured
        }
        guard var components = URLComponents(string: provider.baseURL + path) else {
            throw MiniMaxError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MiniMaxError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiniMaxError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let baseResp = errorBody?["base_resp"] as? [String: Any]
            let statusMsg = baseResp?["status_msg"] as? String ?? "Unknown error"
            let statusCode = baseResp?["status_code"] as? Int ?? httpResponse.statusCode
            throw MiniMaxError.apiError(code: statusCode, message: statusMsg)
        }

        // Check API-level errors in base_resp even when HTTP 200
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let baseResp = json["base_resp"] as? [String: Any],
           let statusCode = baseResp["status_code"] as? Int,
           statusCode != 0 {
            let statusMsg = baseResp["status_msg"] as? String ?? "Unknown API error"
            throw MiniMaxError.apiError(code: statusCode, message: statusMsg)
        }

        return (data, httpResponse)
    }

    // MARK: - Chat Completion

    public struct ChatMessage {
        public let role: String
        public let content: String
        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct ChatResponse {
        public let content: String
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
    }

    public func chatCompletion(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) async throws -> ChatResponse {
        let body: [String: Any] = [
            "model": provider.chatModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false
        ]
        let request = try makeRequest(path: "/chat/completions", body: body)
        let (data, _) = try await perform(request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw MiniMaxError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        return ChatResponse(
            content: content,
            promptTokens: usage?["prompt_tokens"] as? Int ?? 0,
            completionTokens: usage?["completion_tokens"] as? Int ?? 0,
            totalTokens: usage?["total_tokens"] as? Int ?? 0
        )
    }

    /// Streams chat completion, yielding content deltas via the callback.
    public func chatCompletionStream(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onDelta: @escaping (String) -> Void
    ) async throws {
        let body: [String: Any] = [
            "model": provider.chatModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": true
        ]
        let request = try makeRequest(path: "/chat/completions", body: body)

        guard provider.isConfigured else { throw MiniMaxError.notConfigured }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MiniMaxError.apiError(code: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Stream request failed")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let lineData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            onDelta(content)
        }
    }

    // MARK: - Text-to-Speech

    public struct TTSResponse {
        public let audioData: Data
        public let format: String
        public let durationMs: Int
    }

    public func textToSpeech(
        text: String,
        voiceId: String = "male-qn-qingse",
        speed: Double = 1.0,
        vol: Double = 1.0,
        pitch: Int = 0,
        format: String = "mp3",
        sampleRate: Int = 32000
    ) async throws -> TTSResponse {
        let body: [String: Any] = [
            "model": provider.speechModel,
            "text": text,
            "voice_setting": [
                "voice_id": voiceId,
                "speed": speed,
                "vol": vol,
                "pitch": pitch
            ],
            "audio_setting": [
                "sample_rate": sampleRate,
                "bitrate": 128000,
                "format": format,
                "channel": 1
            ],
            "output_format": "hex"
        ]
        let request = try makeRequest(path: "/t2a_v2", body: body)
        let (data, _) = try await perform(request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw MiniMaxError.invalidResponse
        }

          if let audioHex = dataObj["audio"] as? String,
              let audioData = decodeHexAudio(audioHex) {
            let extraInfo = json["extra_info"] as? [String: Any]
            let audioLength = extraInfo?["audio_length"] as? Int ?? 0
            return TTSResponse(audioData: audioData, format: format, durationMs: audioLength)
        }

        throw MiniMaxError.invalidResponse
    }

    private func decodeHexAudio(_ hex: String) -> Data? {
        let normalizedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHex.count.isMultiple(of: 2) else {
            return nil
        }

        var audioData = Data(capacity: normalizedHex.count / 2)
        var index = normalizedHex.startIndex

        while index < normalizedHex.endIndex {
            let nextIndex = normalizedHex.index(index, offsetBy: 2)
            guard let byte = UInt8(normalizedHex[index..<nextIndex], radix: 16) else {
                return nil
            }
            audioData.append(byte)
            index = nextIndex
        }

        return audioData
    }

    // MARK: - Image Generation

    public struct ImageResponse {
        public let images: [Data]
    }

    public func generateImage(
        prompt: String,
        aspectRatio: String = "1:1",
        n: Int = 1
    ) async throws -> ImageResponse {
        let body: [String: Any] = [
            "model": provider.imageModel,
            "prompt": prompt,
            "aspect_ratio": aspectRatio,
            "n": n,
            "response_format": "base64"
        ]
        let request = try makeRequest(path: "/image_generation", body: body)
        let (data, _) = try await perform(request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let imageBase64List = dataObj["image_base64"] as? [String] else {
            throw MiniMaxError.invalidResponse
        }

        let images = imageBase64List.compactMap { Data(base64Encoded: $0) }
        guard !images.isEmpty else { throw MiniMaxError.invalidResponse }
        return ImageResponse(images: images)
    }

    // MARK: - Music Generation

    public struct MusicResponse {
        public let audioData: Data?
        public let audioURL: String?
    }

    public func generateMusic(
        prompt: String,
        lyrics: String? = nil,
        format: String = "mp3",
        sampleRate: Int = 44100,
        bitrate: Int = 256000
    ) async throws -> MusicResponse {
        var body: [String: Any] = [
            "model": provider.musicModel,
            "prompt": prompt,
            "audio_setting": [
                "sample_rate": sampleRate,
                "bitrate": bitrate,
                "format": format
            ],
            "output_format": "url"
        ]
        if let lyrics = lyrics, !lyrics.isEmpty {
            body["lyrics"] = lyrics
        }

        let request = try makeRequest(path: "/music_generation", body: body)
        let (data, _) = try await perform(request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw MiniMaxError.invalidResponse
        }

        let status = dataObj["status"] as? Int ?? 0

        // If generation is already complete, extract audio directly
        if status == 2 {
            return try extractMusicResponse(from: dataObj)
        }

        // Otherwise poll for completion using trace_id / task_id
        guard let taskId = extractTaskId(from: json) else {
            throw MiniMaxError.invalidResponse
        }
        return try await pollMusicTask(taskId: taskId)
    }

    /// Extracts a task identifier (trace_id or task_id) from the API response.
    private func extractTaskId(from json: [String: Any]) -> String? {
        for key in ["trace_id", "task_id"] {
            if let str = json[key] as? String { return str }
            if let num = json[key] as? NSNumber { return num.stringValue }
        }
        return nil
    }

    /// Polls the music generation status endpoint until audio is ready.
    private func pollMusicTask(taskId: String) async throws -> MusicResponse {
        let maxAttempts = 90 // up to ~3 minutes at 2s intervals
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 2_000_000_000)

            let request = try makeGetRequest(
                path: "/query/music_generation",
                queryItems: [URLQueryItem(name: "task_id", value: taskId)]
            )
            let (data, _) = try await perform(request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any] else {
                throw MiniMaxError.invalidResponse
            }

            let status = dataObj["status"] as? Int ?? 0
            if status == 2 {
                return try extractMusicResponse(from: dataObj)
            }
        }
        throw MiniMaxError.apiError(code: -1, message: "Music generation timed out after polling")
    }

    /// Parses the completed music generation data object into a MusicResponse.
    private func extractMusicResponse(from dataObj: [String: Any]) throws -> MusicResponse {
        if let audio = dataObj["audio"] as? String, !audio.isEmpty {
            // When output_format is "url", the audio field contains a download URL
            if audio.hasPrefix("http://") || audio.hasPrefix("https://") {
                return MusicResponse(audioData: nil, audioURL: audio)
            }
            // Fallback: try base64 decode for inline audio data
            if let audioData = Data(base64Encoded: audio) {
                return MusicResponse(audioData: audioData, audioURL: nil)
            }
        }
        throw MiniMaxError.invalidResponse
    }

    /// Downloads audio data from a URL (used for music generation results).
    public func downloadAudio(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw MiniMaxError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MiniMaxError.invalidResponse
        }
        return data
    }
}

// MARK: - Error Types

public enum MiniMaxError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case apiError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MiniMax API key not configured. Please set your API key in Settings."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .invalidResponse:
            return "Received an invalid response from MiniMax API."
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        }
    }
}
