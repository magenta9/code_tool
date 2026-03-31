import Foundation

/// HTTP client for MiniMax API endpoints.
public final class MiniMaxAPIClient {
    public static let shared = MiniMaxAPIClient()

    private let session: URLSession
    private let musicSession: URLSession
    private var settings: MiniMaxSettingsStore { MiniMaxSettingsStore.shared }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        let musicConfig = URLSessionConfiguration.default
        musicConfig.timeoutIntervalForRequest = 600
        musicConfig.timeoutIntervalForResource = 900
        // Bypass HTTP proxy for music generation — local proxies often drop
        // idle connections after ~60 s, well before music generation completes.
        musicConfig.connectionProxyDictionary = [:]
        self.musicSession = URLSession(configuration: musicConfig)
    }

    private struct MusicDiagnosticsContext {
        let referenceID: String
        let model: String
        let promptSummary: String
        let lyricsSummary: String
        let format: String
        let sampleRate: Int
        let bitrate: Int
        let taskID: String?

        func metadata(extra: [String: String] = [:]) -> [String: String] {
            var metadata: [String: String] = [
                "model": model,
                "prompt": promptSummary,
                "format": format,
                "sampleRate": String(sampleRate),
                "bitrate": String(bitrate)
            ]

            if !lyricsSummary.isEmpty {
                metadata["lyrics"] = lyricsSummary
            }

            if let taskID {
                metadata["taskID"] = taskID
            }

            for (key, value) in extra where !value.isEmpty {
                metadata[key] = value
            }

            return metadata
        }
    }

    private struct DiagnosticsContext {
        let category: AppLogCategory
        let featureName: String
        let referenceID: String
        let model: String
        let requestSummary: String
        let metadataFields: [String: String]

        func metadata(extra: [String: String] = [:]) -> [String: String] {
            var metadata: [String: String] = [
                "model": model,
                "requestSummary": requestSummary
            ]

            for (key, value) in metadataFields where !value.isEmpty {
                metadata[key] = value
            }

            for (key, value) in extra where !value.isEmpty {
                metadata[key] = value
            }

            return metadata
        }
    }

    // MARK: - Common

    private func makeRequest(path: String, body: [String: Any]) throws -> URLRequest {
        guard settings.isConfigured else {
            throw MiniMaxError.notConfigured
        }
        guard let url = URL(string: settings.baseURL + path) else {
            throw MiniMaxError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func makeGetRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard settings.isConfigured else {
            throw MiniMaxError.notConfigured
        }
        guard var components = URLComponents(string: settings.baseURL + path) else {
            throw MiniMaxError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MiniMaxError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
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
        public let referenceID: String
    }

    public func chatCompletion(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) async throws -> ChatResponse {
        let context = DiagnosticsContext(
            category: .aichat,
            featureName: "AI Chat",
            referenceID: AppLogger.makeReferenceID(),
            model: settings.chatModel,
            requestSummary: Self.chatRequestSummary(messages: messages, temperature: temperature, maxTokens: maxTokens),
            metadataFields: [
                "temperature": Self.decimalString(temperature),
                "maxTokens": String(maxTokens),
                "messageCount": String(messages.count)
            ]
        )
        let body: [String: Any] = [
            "model": settings.chatModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false
        ]

        await logRequestStarted(context: context, stage: "request_chat_completion", endpoint: "/chat/completions")

        let request: URLRequest
        do {
            request = try makeRequest(path: "/chat/completions", body: body)
        } catch {
            throw await makeLoggedRequestError(
                stage: "build_chat_completion_request",
                userMessage: "Chat request failed.",
                underlying: error,
                context: context,
                request: nil,
                responseData: nil,
                startedAt: nil,
                extra: ["endpoint": "/chat/completions"]
            )
        }

        let (data, _) = try await performLoggedRequest(
            request,
            context: context,
            stage: "request_chat_completion",
            userMessage: "Chat request failed."
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw await makeLoggedRequestError(
                stage: "parse_chat_completion_response",
                userMessage: "Chat request failed.",
                underlying: MiniMaxError.invalidResponse,
                context: context,
                request: request,
                responseData: data,
                startedAt: nil,
                extra: [:]
            )
        }

        let usage = json["usage"] as? [String: Any]
        return ChatResponse(
            content: content,
            promptTokens: usage?["prompt_tokens"] as? Int ?? 0,
            completionTokens: usage?["completion_tokens"] as? Int ?? 0,
            totalTokens: usage?["total_tokens"] as? Int ?? 0,
            referenceID: context.referenceID
        )
    }

    /// Streams chat completion, yielding content deltas via the callback.
    public func chatCompletionStream(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        referenceID: String? = nil,
        onDelta: @escaping (String) -> Void
    ) async throws {
        let resolvedReferenceID = referenceID ?? AppLogger.makeReferenceID()
        let context = DiagnosticsContext(
            category: .aichat,
            featureName: "AI Chat",
            referenceID: resolvedReferenceID,
            model: settings.chatModel,
            requestSummary: Self.chatRequestSummary(messages: messages, temperature: temperature, maxTokens: maxTokens),
            metadataFields: [
                "temperature": Self.decimalString(temperature),
                "maxTokens": String(maxTokens),
                "messageCount": String(messages.count)
            ]
        )
        let body: [String: Any] = [
            "model": settings.chatModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": true
        ]

        await logRequestStarted(context: context, stage: "stream_chat_completion", endpoint: "/chat/completions")

        let request: URLRequest
        do {
            request = try makeRequest(path: "/chat/completions", body: body)
        } catch {
            throw await makeLoggedRequestError(
                stage: "build_chat_completion_stream_request",
                userMessage: "Chat request failed.",
                underlying: error,
                context: context,
                request: nil,
                responseData: nil,
                startedAt: nil,
                extra: ["endpoint": "/chat/completions"]
            )
        }

        let startedAt = Date()

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiniMaxError.invalidResponse
            }
            if httpResponse.statusCode != 200 {
                let responseData = try await collectResponseData(from: bytes)
                let errorBody = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                let baseResp = errorBody?["base_resp"] as? [String: Any]
                let statusMsg = baseResp?["status_msg"] as? String ?? "Stream request failed"
                let statusCode = baseResp?["status_code"] as? Int ?? httpResponse.statusCode
                throw await makeLoggedRequestError(
                    stage: "stream_chat_completion",
                    userMessage: "Chat request failed.",
                    underlying: MiniMaxError.apiError(code: statusCode, message: statusMsg),
                    context: context,
                    request: request,
                    responseData: responseData,
                    startedAt: startedAt,
                    extra: ["httpStatus": String(httpResponse.statusCode)]
                )
            }

            var chunkCount = 0
            var completionCharacters = 0

            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                guard let lineData = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String else { continue }
                chunkCount += 1
                completionCharacters += content.count
                onDelta(content)
            }

            await AppLogger.shared.info(
                category: context.category,
                event: "request_finished",
                referenceID: context.referenceID,
                message: "AI Chat stream completed.",
                metadata: context.metadata(extra: [
                    "stage": "stream_chat_completion",
                    "url": request.url?.absoluteString ?? "",
                    "method": request.httpMethod ?? "",
                    "durationMs": Self.durationMSString(since: startedAt),
                    "httpStatus": String(httpResponse.statusCode),
                    "chunkCount": String(chunkCount),
                    "completionCharacters": String(completionCharacters)
                ])
            )
        } catch {
            if let loggedError = error as? LoggedDiagnosticError {
                throw loggedError
            }

            throw await makeLoggedRequestError(
                stage: "stream_chat_completion",
                userMessage: "Chat request failed.",
                underlying: error,
                context: context,
                request: request,
                responseData: nil,
                startedAt: startedAt,
                extra: [:]
            )
        }
    }

    // MARK: - Text-to-Speech

    public struct TTSResponse {
        public let audioData: Data
        public let format: String
        public let durationMs: Int
        public let referenceID: String
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
        let context = DiagnosticsContext(
            category: .aispeech,
            featureName: "AI Speech",
            referenceID: AppLogger.makeReferenceID(),
            model: settings.speechModel,
            requestSummary: Self.speechRequestSummary(
                text: text,
                voiceId: voiceId,
                speed: speed,
                volume: vol,
                pitch: pitch,
                format: format,
                sampleRate: sampleRate
            ),
            metadataFields: [
                "voiceId": voiceId,
                "format": format,
                "sampleRate": String(sampleRate),
                "speed": Self.decimalString(speed),
                "volume": Self.decimalString(vol),
                "pitch": String(pitch)
            ]
        )
        let body: [String: Any] = [
            "model": settings.speechModel,
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

        await logRequestStarted(context: context, stage: "request_text_to_speech", endpoint: "/t2a_v2")

        let request: URLRequest
        do {
            request = try makeRequest(path: "/t2a_v2", body: body)
        } catch {
            throw await makeLoggedRequestError(
                stage: "build_text_to_speech_request",
                userMessage: "Speech generation failed.",
                underlying: error,
                context: context,
                request: nil,
                responseData: nil,
                startedAt: nil,
                extra: ["endpoint": "/t2a_v2"]
            )
        }

        let (data, _) = try await performLoggedRequest(
            request,
            context: context,
            stage: "request_text_to_speech",
            userMessage: "Speech generation failed."
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw await makeLoggedRequestError(
                stage: "parse_text_to_speech_response",
                userMessage: "Speech generation failed.",
                underlying: MiniMaxError.invalidResponse,
                context: context,
                request: request,
                responseData: data,
                startedAt: nil,
                extra: [:]
            )
        }

        if let audioHex = dataObj["audio"] as? String,
           let audioData = decodeHexAudio(audioHex) {
            let extraInfo = json["extra_info"] as? [String: Any]
            let audioLength = extraInfo?["audio_length"] as? Int ?? 0
            return TTSResponse(
                audioData: audioData,
                format: format,
                durationMs: audioLength,
                referenceID: context.referenceID
            )
        }

        throw await makeLoggedRequestError(
            stage: "decode_text_to_speech_audio",
            userMessage: "Speech generation failed.",
            underlying: MiniMaxError.invalidResponse,
            context: context,
            request: request,
            responseData: data,
            startedAt: nil,
            extra: [:]
        )
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
        public let referenceID: String
    }

    public func generateImage(
        prompt: String,
        aspectRatio: String = "1:1",
        n: Int = 1
    ) async throws -> ImageResponse {
        let context = DiagnosticsContext(
            category: .aiimage,
            featureName: "AI Image",
            referenceID: AppLogger.makeReferenceID(),
            model: settings.imageModel,
            requestSummary: Self.imageRequestSummary(prompt: prompt, aspectRatio: aspectRatio, n: n),
            metadataFields: [
                "aspectRatio": aspectRatio,
                "imageCount": String(n)
            ]
        )
        let body: [String: Any] = [
            "model": settings.imageModel,
            "prompt": prompt,
            "aspect_ratio": aspectRatio,
            "n": n,
            "response_format": "base64"
        ]

        await logRequestStarted(context: context, stage: "request_image_generation", endpoint: "/image_generation")

        let request: URLRequest
        do {
            request = try makeRequest(path: "/image_generation", body: body)
        } catch {
            throw await makeLoggedRequestError(
                stage: "build_image_generation_request",
                userMessage: "Image generation failed.",
                underlying: error,
                context: context,
                request: nil,
                responseData: nil,
                startedAt: nil,
                extra: ["endpoint": "/image_generation"]
            )
        }

        let (data, _) = try await performLoggedRequest(
            request,
            context: context,
            stage: "request_image_generation",
            userMessage: "Image generation failed."
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let imageBase64List = dataObj["image_base64"] as? [String] else {
            throw await makeLoggedRequestError(
                stage: "parse_image_generation_response",
                userMessage: "Image generation failed.",
                underlying: MiniMaxError.invalidResponse,
                context: context,
                request: request,
                responseData: data,
                startedAt: nil,
                extra: [:]
            )
        }

        let images = imageBase64List.compactMap { Data(base64Encoded: $0) }
        guard !images.isEmpty else {
            throw await makeLoggedRequestError(
                stage: "decode_image_generation_response",
                userMessage: "Image generation failed.",
                underlying: MiniMaxError.invalidResponse,
                context: context,
                request: request,
                responseData: data,
                startedAt: nil,
                extra: [:]
            )
        }
        return ImageResponse(images: images, referenceID: context.referenceID)
    }

    // MARK: - Music Generation

    public struct MusicResponse {
        public let audioData: Data?
        public let audioURL: String?
        public let referenceID: String
        public let taskID: String?
    }

    public func generateMusic(
        prompt: String,
        lyrics: String? = nil,
        isInstrumental: Bool = false,
        format: String = "mp3",
        sampleRate: Int = 44100,
        bitrate: Int = 256000
    ) async throws -> MusicResponse {
        let context = MusicDiagnosticsContext(
            referenceID: AppLogger.makeReferenceID(),
            model: settings.musicModel,
            promptSummary: Self.redactedPromptSummary(prompt),
            lyricsSummary: Self.redactedLyricsSummary(lyrics),
            format: format,
            sampleRate: sampleRate,
            bitrate: bitrate,
            taskID: nil
        )

        var body: [String: Any] = [
            "model": settings.musicModel,
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
        } else if isInstrumental {
            body["is_instrumental"] = true
        }

        let requestSummary = Self.musicRequestSummary(prompt: prompt, lyrics: lyrics, format: format, sampleRate: sampleRate, bitrate: bitrate)

        await AppLogger.shared.info(
            category: .aimusic,
            event: "request_started",
            referenceID: context.referenceID,
            message: "Started MiniMax music generation request.",
            metadata: context.metadata(extra: [
                "endpoint": "/music_generation",
                "requestSummary": requestSummary
            ])
        )

        var request: URLRequest
        do {
            request = try makeRequest(path: "/music_generation", body: body)
        } catch {
            throw await makeLoggedMusicError(
                stage: "build_music_generation_request",
                userMessage: "Music generation failed.",
                underlying: error,
                context: context,
                request: nil,
                responseData: nil,
                startedAt: nil,
                extra: ["endpoint": "/music_generation"]
            )
        }
        // Music generation can take several minutes; override default 60s timeout.
        request.timeoutInterval = 600

        let startedAt = Date()

        do {
            let (data, response) = try await musicSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiniMaxError.invalidResponse
            }
            if httpResponse.statusCode != 200 {
                let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let baseResp = errorBody?["base_resp"] as? [String: Any]
                let statusMsg = baseResp?["status_msg"] as? String ?? "Unknown error"
                let statusCode = baseResp?["status_code"] as? Int ?? httpResponse.statusCode
                throw await makeLoggedMusicError(
                    stage: "request_music_generation",
                    userMessage: "Music generation failed.",
                    underlying: MiniMaxError.apiError(code: statusCode, message: statusMsg),
                    context: context,
                    request: request,
                    responseData: data,
                    startedAt: startedAt,
                    extra: [
                        "httpStatus": String(httpResponse.statusCode),
                        "requestSummary": requestSummary
                    ]
                )
            }

            // Check API-level errors in base_resp even when HTTP 200
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let baseResp = json["base_resp"] as? [String: Any],
               let statusCode = baseResp["status_code"] as? Int,
               statusCode != 0 {
                let statusMsg = baseResp["status_msg"] as? String ?? "Unknown API error"
                throw await makeLoggedMusicError(
                    stage: "request_music_generation",
                    userMessage: "Music generation failed.",
                    underlying: MiniMaxError.apiError(code: statusCode, message: statusMsg),
                    context: context,
                    request: request,
                    responseData: data,
                    startedAt: startedAt,
                    extra: [
                        "httpStatus": String(httpResponse.statusCode),
                        "requestSummary": requestSummary,
                        "responseSummary": Self.summarizeJSONData(data)
                    ]
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataObj = json["data"] as? [String: Any] else {
                throw await makeLoggedMusicError(
                    stage: "parse_music_generation_response",
                    userMessage: "Music generation failed.",
                    underlying: MiniMaxError.invalidResponse,
                    context: context,
                    request: request,
                    responseData: data,
                    startedAt: startedAt,
                    extra: [
                        "httpStatus": String(httpResponse.statusCode),
                        "responseSummary": Self.summarizeJSONData(data)
                    ]
                )
            }

            if let audioValue = dataObj["audio"] as? String, !audioValue.isEmpty {
                if audioValue.hasPrefix("http://") || audioValue.hasPrefix("https://") {
                    await AppLogger.shared.info(
                        category: .aimusic,
                        event: "request_finished",
                        referenceID: context.referenceID,
                        message: "MiniMax music generation completed.",
                        metadata: context.metadata(extra: [
                            "stage": "request_music_generation",
                            "durationMs": Self.durationMSString(since: startedAt),
                            "httpStatus": String(httpResponse.statusCode),
                            "audioURL": AppLogger.summarize(text: audioValue),
                            "requestSummary": requestSummary
                        ])
                    )

                    return MusicResponse(audioData: nil, audioURL: audioValue, referenceID: context.referenceID, taskID: nil)
                }

                if let audioData = decodeHexAudio(audioValue) {
                    await AppLogger.shared.info(
                        category: .aimusic,
                        event: "request_finished",
                        referenceID: context.referenceID,
                        message: "MiniMax music generation completed.",
                        metadata: context.metadata(extra: [
                            "stage": "request_music_generation",
                            "durationMs": Self.durationMSString(since: startedAt),
                            "httpStatus": String(httpResponse.statusCode),
                            "audioBytes": String(audioData.count),
                            "requestSummary": requestSummary
                        ])
                    )

                    return MusicResponse(audioData: audioData, audioURL: nil, referenceID: context.referenceID, taskID: nil)
                }

                throw await makeLoggedMusicError(
                    stage: "decode_music_audio",
                    userMessage: "Music generation failed.",
                    underlying: MiniMaxError.invalidResponse,
                    context: context,
                    request: request,
                    responseData: nil,
                    startedAt: startedAt,
                    extra: [
                        "audioPreview": AppLogger.summarize(text: audioValue),
                        "audioLength": String(audioValue.count)
                    ]
                )
            }

            if let audioURL = dataObj["audio_url"] as? String, !audioURL.isEmpty {
                await AppLogger.shared.info(
                    category: .aimusic,
                    event: "request_finished",
                    referenceID: context.referenceID,
                    message: "MiniMax music generation completed.",
                    metadata: context.metadata(extra: [
                        "stage": "request_music_generation",
                        "durationMs": Self.durationMSString(since: startedAt),
                        "httpStatus": String(httpResponse.statusCode),
                        "audioURL": AppLogger.summarize(text: audioURL),
                        "requestSummary": requestSummary
                    ])
                )

                return MusicResponse(audioData: nil, audioURL: audioURL, referenceID: context.referenceID, taskID: nil)
            }

            throw await makeLoggedMusicError(
                stage: "parse_music_generation_response",
                userMessage: "Music generation failed.",
                underlying: MiniMaxError.invalidResponse,
                context: context,
                request: request,
                responseData: data,
                startedAt: startedAt,
                extra: [
                    "httpStatus": String(httpResponse.statusCode),
                    "responseSummary": Self.summarizeJSONData(data)
                ]
            )
        } catch {
            if let loggedError = error as? LoggedDiagnosticError {
                throw loggedError
            }

            throw await makeLoggedMusicError(
                stage: "request_music_generation",
                userMessage: "Music generation failed.",
                underlying: error,
                context: context,
                request: request,
                responseData: nil,
                startedAt: startedAt,
                extra: ["requestSummary": requestSummary]
            )
        }
    }

    /// Downloads audio data from a URL (used for music generation results).
    public func downloadAudio(from urlString: String, referenceID: String? = nil, taskID: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw MiniMaxError.invalidURL
        }
        let startedAt = Date()

        if let referenceID {
            await AppLogger.shared.info(
                category: .aimusic,
                event: "download_started",
                referenceID: referenceID,
                message: "Started downloading generated music audio.",
                metadata: [
                    "taskID": taskID ?? "",
                    "audioURL": AppLogger.summarize(text: url.absoluteString)
                ]
            )
        }

        do {
            let (data, response) = try await musicSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw MiniMaxError.invalidResponse
            }

            if let referenceID {
                await AppLogger.shared.info(
                    category: .aimusic,
                    event: "download_finished",
                    referenceID: referenceID,
                    message: "Downloaded generated music audio.",
                    metadata: [
                        "taskID": taskID ?? "",
                        "audioURL": AppLogger.summarize(text: url.absoluteString),
                        "durationMs": Self.durationMSString(since: startedAt),
                        "httpStatus": String(httpResponse.statusCode),
                        "byteCount": String(data.count)
                    ]
                )
            }

            return data
        } catch {
            if let referenceID {
                let resolvedReferenceID = await AppLogger.shared.error(
                    category: .aimusic,
                    event: "download_failed",
                    referenceID: referenceID,
                    message: "Failed to download generated music audio.",
                    metadata: [
                        "taskID": taskID ?? "",
                        "audioURL": AppLogger.summarize(text: url.absoluteString),
                        "durationMs": Self.durationMSString(since: startedAt)
                    ],
                    error: error
                )

                throw LoggedDiagnosticError(
                    referenceID: resolvedReferenceID,
                    userMessage: "Music download failed.",
                    category: .aimusic,
                    stage: "download_music_audio",
                    underlyingError: error
                )
            }

            throw error
        }
    }

    private func makeLoggedMusicError(
        stage: String,
        userMessage: String,
        underlying: Error,
        context: MusicDiagnosticsContext,
        request: URLRequest?,
        responseData: Data?,
        startedAt: Date?,
        extra: [String: String]
    ) async -> LoggedDiagnosticError {
        let resolvedReferenceID = await AppLogger.shared.error(
            category: .aimusic,
            event: "music_request_failed",
            referenceID: context.referenceID,
            message: "AIMusic request failed at stage \(stage).",
            metadata: context.metadata(extra: extra.merging([
                "stage": stage,
                "url": request?.url?.absoluteString ?? "",
                "method": request?.httpMethod ?? "",
                "durationMs": startedAt.map(Self.durationMSString(since:)) ?? "",
                "responseSummary": responseData.map(Self.summarizeJSONData) ?? ""
            ], uniquingKeysWith: { _, new in new })),
            error: underlying
        )

        return LoggedDiagnosticError(
            referenceID: resolvedReferenceID,
            userMessage: userMessage,
            category: .aimusic,
            stage: stage,
            underlyingError: underlying
        )
    }

    private func logRequestStarted(context: DiagnosticsContext, stage: String, endpoint: String) async {
        await AppLogger.shared.info(
            category: context.category,
            event: "request_started",
            referenceID: context.referenceID,
            message: "Started \(context.featureName) request.",
            metadata: context.metadata(extra: [
                "stage": stage,
                "endpoint": endpoint
            ])
        )
    }

    private func performLoggedRequest(
        _ request: URLRequest,
        context: DiagnosticsContext,
        stage: String,
        userMessage: String
    ) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Date()

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MiniMaxError.invalidResponse
            }
            if httpResponse.statusCode != 200 {
                let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let baseResp = errorBody?["base_resp"] as? [String: Any]
                let statusMsg = baseResp?["status_msg"] as? String ?? "Unknown error"
                let statusCode = baseResp?["status_code"] as? Int ?? httpResponse.statusCode
                throw await makeLoggedRequestError(
                    stage: stage,
                    userMessage: userMessage,
                    underlying: MiniMaxError.apiError(code: statusCode, message: statusMsg),
                    context: context,
                    request: request,
                    responseData: data,
                    startedAt: startedAt,
                    extra: ["httpStatus": String(httpResponse.statusCode)]
                )
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let baseResp = json["base_resp"] as? [String: Any],
               let statusCode = baseResp["status_code"] as? Int,
               statusCode != 0 {
                let statusMsg = baseResp["status_msg"] as? String ?? "Unknown API error"
                throw await makeLoggedRequestError(
                    stage: stage,
                    userMessage: userMessage,
                    underlying: MiniMaxError.apiError(code: statusCode, message: statusMsg),
                    context: context,
                    request: request,
                    responseData: data,
                    startedAt: startedAt,
                    extra: ["httpStatus": String(httpResponse.statusCode)]
                )
            }

            await AppLogger.shared.info(
                category: context.category,
                event: "request_finished",
                referenceID: context.referenceID,
                message: "\(context.featureName) request completed.",
                metadata: context.metadata(extra: [
                    "stage": stage,
                    "url": request.url?.absoluteString ?? "",
                    "method": request.httpMethod ?? "",
                    "durationMs": Self.durationMSString(since: startedAt),
                    "httpStatus": String(httpResponse.statusCode),
                    "responseSummary": Self.summarizeJSONData(data)
                ])
            )

            return (data, httpResponse)
        } catch {
            if let loggedError = error as? LoggedDiagnosticError {
                throw loggedError
            }

            throw await makeLoggedRequestError(
                stage: stage,
                userMessage: userMessage,
                underlying: error,
                context: context,
                request: request,
                responseData: nil,
                startedAt: startedAt,
                extra: [:]
            )
        }
    }

    private func makeLoggedRequestError(
        stage: String,
        userMessage: String,
        underlying: Error,
        context: DiagnosticsContext,
        request: URLRequest?,
        responseData: Data?,
        startedAt: Date?,
        extra: [String: String]
    ) async -> LoggedDiagnosticError {
        let resolvedReferenceID = await AppLogger.shared.error(
            category: context.category,
            event: "request_failed",
            referenceID: context.referenceID,
            message: "\(context.featureName) request failed at stage \(stage).",
            metadata: context.metadata(extra: extra.merging([
                "stage": stage,
                "url": request?.url?.absoluteString ?? "",
                "method": request?.httpMethod ?? "",
                "durationMs": startedAt.map(Self.durationMSString(since:)) ?? "",
                "responseSummary": responseData.map(Self.summarizeJSONData) ?? ""
            ], uniquingKeysWith: { _, new in new })),
            error: underlying
        )

        return LoggedDiagnosticError(
            referenceID: resolvedReferenceID,
            userMessage: userMessage,
            category: context.category,
            stage: stage,
            underlyingError: underlying
        )
    }

    private func collectResponseData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private static func chatRequestSummary(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> String {
        [
            "messages=\(chatMessagesSummary(messages))",
            "temperature=\(decimalString(temperature))",
            "maxTokens=\(maxTokens)"
        ].joined(separator: ", ")
    }

    private static func speechRequestSummary(
        text: String,
        voiceId: String,
        speed: Double,
        volume: Double,
        pitch: Int,
        format: String,
        sampleRate: Int
    ) -> String {
        [
            "text=\(redactedUserInputSummary(text))",
            "voiceId=\(voiceId)",
            "speed=\(decimalString(speed))",
            "volume=\(decimalString(volume))",
            "pitch=\(pitch)",
            "format=\(format)",
            "sampleRate=\(sampleRate)"
        ].joined(separator: ", ")
    }

    private static func imageRequestSummary(prompt: String, aspectRatio: String, n: Int) -> String {
        [
            "prompt=\(redactedUserInputSummary(prompt))",
            "aspectRatio=\(aspectRatio)",
            "imageCount=\(n)"
        ].joined(separator: ", ")
    }

    private static func chatMessagesSummary(_ messages: [ChatMessage]) -> String {
        guard !messages.isEmpty else {
            return "count=0"
        }

        let recentMessages = messages.suffix(4).map { message in
            let summary = redactedUserInputSummary(message.content)
            return "\(message.role){\(summary.isEmpty ? "empty" : summary)}"
        }

        return "count=\(messages.count), recent=\(recentMessages.joined(separator: " | "))"
    }

    private static func musicRequestSummary(
        prompt: String,
        lyrics: String?,
        format: String,
        sampleRate: Int,
        bitrate: Int
    ) -> String {
        var parts = [
            "prompt=\(redactedPromptSummary(prompt))",
            "format=\(format)",
            "sampleRate=\(sampleRate)",
            "bitrate=\(bitrate)"
        ]

        let lyricsSummary = redactedLyricsSummary(lyrics)
        if !lyricsSummary.isEmpty {
            parts.append("lyrics=\(lyricsSummary)")
        }

        return parts.joined(separator: ", ")
    }

    private static func redactedPromptSummary(_ prompt: String) -> String {
        redactedUserInputSummary(prompt)
    }

    private static func redactedLyricsSummary(_ lyrics: String?) -> String {
        redactedUserInputSummary(lyrics)
    }

    private static func redactedUserInputSummary(_ text: String?, previewLimit: Int = 24) -> String {
        guard let text else {
            return ""
        }

        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return ""
        }

        let lineCount = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        var parts = [
            "len=\(normalized.count)",
            "lines=\(lineCount)"
        ]

        if normalized.count > previewLimit {
            let endIndex = normalized.index(normalized.startIndex, offsetBy: previewLimit)
            parts.append("prefix=\(String(normalized[..<endIndex]))…")
        }

        return parts.joined(separator: ", ")
    }

    private static func summarizeJSONData(_ data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return AppLogger.summarize(text: string, limit: 240)
        }
        return "<non-utf8 body size=\(data.count)>"
    }

    private static func decimalString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private static func durationMSString(since startDate: Date) -> String {
        String(Int(Date().timeIntervalSince(startDate) * 1000))
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
