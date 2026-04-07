import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

#if canImport(AppKit)
    import AppKit
#endif

extension CodeToolTests {
    func testTextToSpeechRequestsHexOutputAndDecodesHexAudio() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/t2a_v2")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(bodyObject["output_format"] as? String, "hex")

            let audioSetting = try XCTUnwrap(bodyObject["audio_setting"] as? [String: Any])
            XCTAssertEqual(audioSetting["format"] as? String, "mp3")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
                "data": [
                    "audio": "48656c6c6f"
                ],
                "extra_info": [
                    "audio_length": 321
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.textToSpeech(text: "Hello")

        XCTAssertEqual(response.audioData, Data("Hello".utf8))
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.durationMs, 321)
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testTextToSpeechStreamSendsWebSocketEventsAndDecodesChunks() async throws {
        let socket = MockWebSocket(receivedMessages: [
            .string(#"{"event":"connected_success"}"#),
            .string(#"{"event":"task_started"}"#),
            .string(#"{"data":{"audio":"48656c"}}"#),
            .string(#"{"data":{"audio":"6c6f"},"extra_info":{"audio_length":321},"is_final":true}"#),
        ])

        var capturedRequest: URLRequest?
        let streamingClient = MiniMaxAPIClient.makeTestingClient(urlProtocolType: MockURLProtocol.self) { request in
            capturedRequest = request
            return socket
        }

        var chunks: [Data] = []
        let response = try await streamingClient.textToSpeechStream(text: "Hello", referenceID: "stream-ref-001") {
            chunks.append($0)
        }

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "wss://example.com/ws/v1/t2a_v2")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(chunks, [Data("Hel".utf8), Data("lo".utf8)])
        XCTAssertEqual(response.audioData, Data("Hello".utf8))
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.durationMs, 321)
        XCTAssertEqual(response.referenceID, "stream-ref-001")
        XCTAssertEqual(socket.closeCode, .normalClosure)

        XCTAssertEqual(socket.sentPayloads.count, 3)
        let taskStart = try socket.sentJSONObject(at: 0)
        let taskContinue = try socket.sentJSONObject(at: 1)
        let taskFinish = try socket.sentJSONObject(at: 2)

        XCTAssertEqual(taskStart["event"] as? String, "task_start")
        XCTAssertEqual(taskStart["model"] as? String, MiniMaxSettingsStore.shared.speechModel)
        XCTAssertEqual((taskStart["audio_setting"] as? [String: Any])?["format"] as? String, "mp3")
        XCTAssertEqual(taskContinue["event"] as? String, "task_continue")
        XCTAssertEqual(taskContinue["text"] as? String, "Hello")
        XCTAssertEqual(taskFinish["event"] as? String, "task_finish")
    }

    func testTextToSpeechStreamErrorWritesStructuredLog() async throws {
        let referenceID = "stream-error-ref-001"
        let socket = MockWebSocket(receivedMessages: [
            .string(#"{"event":"connected_success"}"#),
            .string(#"{"event":"task_started"}"#),
            .string(#"{"event":"task_failed","message":"stream rate limited"}"#),
        ])

        let streamingClient = MiniMaxAPIClient.makeTestingClient(urlProtocolType: MockURLProtocol.self) { _ in
            socket
        }

        do {
            _ = try await streamingClient.textToSpeechStream(text: "private speech text", referenceID: referenceID) { _ in }
            XCTFail("Expected textToSpeechStream to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID: \(referenceID)"))

            let content = try await logContent(for: .aispeech)
            XCTAssertTrue(content.contains("request_started"))
            XCTAssertTrue(content.contains("request_failed"))
            XCTAssertTrue(content.contains("stream_text_to_speech"))
            XCTAssertTrue(content.contains(referenceID))
            XCTAssertFalse(content.contains("private speech text"))
        }

        XCTAssertEqual(socket.closeCode, .goingAway)
    }

    func testStreamingSpeechPlayerRejectsIncompleteMP3Playback() throws {
        let player = StreamingSpeechPlayer()
        player.reset(format: "mp3")
        player.append(Data([0x49, 0x44, 0x33, 0x04]))

        XCTAssertThrowsError(try player.play()) { error in
            XCTAssertTrue(error.localizedDescription.contains("Playback becomes available after the full audio finishes generating."))
        }
    }

    func testTextToSpeechTimeoutWritesStructuredErrorLog() async throws {
        let sensitiveText = "private speech text"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/t2a_v2")
            throw URLError(.timedOut)
        }

        do {
            _ = try await miniMaxClient.textToSpeech(text: sensitiveText)
            XCTFail("Expected textToSpeech to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let content = try await logContent(for: .aispeech)
            XCTAssertTrue(content.contains("request_started"))
            XCTAssertTrue(content.contains("request_failed"))
            XCTAssertTrue(content.contains("request_text_to_speech"))
            XCTAssertTrue(content.contains("NSURLErrorDomain"))
            XCTAssertFalse(content.contains(sensitiveText))
        }
    }

    func testGenerateImageAPIErrorWritesStructuredErrorLog() async throws {
        let sensitivePrompt = "private image prompt"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/image_generation")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 4001,
                    "status_msg": "invalid prompt",
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 500, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        do {
            _ = try await miniMaxClient.generateImage(prompt: sensitivePrompt)
            XCTFail("Expected generateImage to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let content = try await logContent(for: .aiimage)
            XCTAssertTrue(content.contains("request_started"))
            XCTAssertTrue(content.contains("request_failed"))
            XCTAssertTrue(content.contains("request_image_generation"))
            XCTAssertTrue(content.contains("4001"))
            XCTAssertFalse(content.contains(sensitivePrompt))
        }
    }

    func testGenerateImageRequestIncludesSubjectReference() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/image_generation")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            let subjectReference = try XCTUnwrap((bodyObject["subject_reference"] as? [[String: Any]])?.first)
            XCTAssertEqual(subjectReference["type"] as? String, "character")
            let imageFile = try XCTUnwrap(subjectReference["image_file"] as? String)
            XCTAssertTrue(imageFile.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(imageFile.contains("ZmFrZQ=="))

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
                "data": [
                    "image_base64": [Self.tinyPNGBase64]
                ],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateImage(
            request: MiniMaxAPIClient.MiniMaxImageGenerationRequest(
                prompt: "Reference portrait",
                aspectRatio: "16:9",
                subjectReferences: [MiniMaxAPIClient.MiniMaxSubjectReference(imageBase64: "ZmFrZQ==")]
            )
        )

        XCTAssertEqual(response.images.count, 1)
    }

    func testGenerateImageRequestIncludesAdvancedParameters() async throws {
        MockURLProtocol.requestHandler = { request in
            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            XCTAssertEqual(bodyObject["seed"] as? Int, 42)
            XCTAssertEqual(bodyObject["prompt_optimizer"] as? Bool, true)
            XCTAssertEqual(bodyObject["n"] as? Int, 3)
            XCTAssertEqual(bodyObject["aspect_ratio"] as? String, "9:16")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
                "data": [
                    "image_base64": [Self.tinyPNGBase64]
                ],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateImage(
            request: MiniMaxAPIClient.MiniMaxImageGenerationRequest(
                prompt: "High fashion silhouette",
                aspectRatio: "9:16",
                imageCount: 3,
                seed: 42,
                promptOptimizer: true
            )
        )

        XCTAssertEqual(response.images.count, 1)
    }

    func testGenerateImageRequestUsesCustomSizeWhenSelected() async throws {
        MockURLProtocol.requestHandler = { request in
            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            XCTAssertEqual(bodyObject["width"] as? Int, 1536)
            XCTAssertEqual(bodyObject["height"] as? Int, 1024)
            XCTAssertNil(bodyObject["aspect_ratio"])

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
                "data": [
                    "image_base64": [Self.tinyPNGBase64]
                ],
            ]
            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateImage(
            request: MiniMaxAPIClient.MiniMaxImageGenerationRequest(
                prompt: "Custom canvas composition",
                width: 1536,
                height: 1024,
                imageCount: 2
            )
        )

        XCTAssertEqual(response.images.count, 1)
    }

    func testImageHistoryRecordCodableWithReferenceImages() throws {
        let record = ImageHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            prompt: "Editorial portrait",
            aspectRatio: nil,
            width: 1536,
            height: 1024,
            imageCount: 2,
            seed: 99,
            promptOptimizer: true,
            model: "image-01",
            referenceImages: [
                ImageReferenceRecord(fileName: "record-ref-0.png", mimeType: "image/png", sizeBytes: 2048)
            ],
            outputImageFileNames: ["record-out-0.png", "record-out-1.png"],
            referenceID: "img-ref-001"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ImageHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.prompt, record.prompt)
        XCTAssertEqual(decoded.width, 1536)
        XCTAssertEqual(decoded.height, 1024)
        XCTAssertEqual(decoded.seed, 99)
        XCTAssertTrue(decoded.promptOptimizer)
        XCTAssertEqual(decoded.referenceImages.count, 1)
        XCTAssertEqual(decoded.referenceImages.first?.fileName, "record-ref-0.png")
        XCTAssertEqual(decoded.outputImageFileNames, ["record-out-0.png", "record-out-1.png"])
    }

    func testImageHistoryRecordDecodesLegacyImageFileNames() throws {
        let json = """
        {
          "id": "B3B7B6A9-7A7F-42D2-8D54-CA8E77F594B1",
          "createdAt": "2026-04-03T00:00:00Z",
          "prompt": "Legacy prompt",
          "aspectRatio": "1:1",
          "imageCount": 1,
          "model": "image-01",
          "imageFileNames": ["legacy-out-0.png"],
          "referenceID": "legacy-image-ref"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ImageHistoryRecord.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.outputImageFileNames, ["legacy-out-0.png"])
        XCTAssertEqual(decoded.referenceImages.count, 0)
        XCTAssertFalse(decoded.promptOptimizer)
    }

    func testChatCompletionStreamAPIErrorWritesStructuredErrorLog() async throws {
        let sensitivePrompt = "private chat prompt"
        let referenceID = "chat-ref-001"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 4290,
                    "status_msg": "rate limited",
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        do {
            try await miniMaxClient.chatCompletionStream(
                messages: [MiniMaxAPIClient.ChatMessage(role: "user", content: sensitivePrompt)],
                referenceID: referenceID
            ) { _ in }
            XCTFail("Expected chatCompletionStream to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID: \(referenceID)"))

            let content = try await logContent(for: .aichat)
            XCTAssertTrue(content.contains("request_started"))
            XCTAssertTrue(content.contains("request_failed"))
            XCTAssertTrue(content.contains("stream_chat_completion"))
            XCTAssertTrue(content.contains(referenceID))
            XCTAssertFalse(content.contains(sensitivePrompt))
        }
    }

    func testGenerateMusicWithLyricsUsesURLTransportAndParsesAudioURL() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(bodyObject["output_format"] as? String, "url")
            XCTAssertNil(bodyObject["lyrics_optimizer"])
            XCTAssertNotNil(bodyObject["lyrics"])

            let audioSetting = try XCTUnwrap(bodyObject["audio_setting"] as? [String: Any])
            XCTAssertEqual(audioSetting["sample_rate"] as? Int, 44100)
            XCTAssertEqual(audioSetting["bitrate"] as? Int, 256000)
            XCTAssertEqual(audioSetting["format"] as? String, "mp3")

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "https://example.com/generated-with-lyrics.mp3",
                    "status": 2,
                ],
                "trace_id": "trace-123",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateMusic(prompt: "folk song", lyrics: "[Verse]\nHello world")

        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated-with-lyrics.mp3")
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicTimeoutWritesStructuredErrorLog() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            throw URLError(.timedOut)
        }

        do {
            _ = try await miniMaxClient.generateMusic(prompt: "slow orchestral soundtrack")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logFiles = await AppLogger.shared.logFileURLs(for: .aimusic)
            XCTAssertEqual(logFiles.count, 1)

            let content = try XCTUnwrap(String(data: Data(contentsOf: try XCTUnwrap(logFiles.first)), encoding: .utf8))
            XCTAssertTrue(content.contains("request_started"))
            XCTAssertTrue(content.contains("music_request_failed"))
            XCTAssertTrue(content.contains("request_music_generation"))
            XCTAssertTrue(content.contains("NSURLErrorDomain"))
            XCTAssertTrue(content.contains("-1001"))
            XCTAssertTrue(content.contains("stackTrace"))
        }
    }

    func testGenerateMusicUnsupportedModelSurfacesActionableError() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let responseBody: [String: Any] = [
                "data": NSNull(),
                "trace_id": "trace-unsupported-model",
                "base_resp": [
                    "status_code": 2061,
                    "status_msg": "your current token plan not support model, music-2.5+",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        do {
            _ = try await miniMaxClient.generateMusic(prompt: "dark piano")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Current MiniMax token plan does not support the configured music model."))
            XCTAssertTrue(error.localizedDescription.contains("MiniMax Settings"))
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }

    func testGenerateMusicNetworkConnectionLostSurfacesIdleTimeoutHint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            throw URLError(.networkConnectionLost)
        }

        do {
            _ = try await miniMaxClient.generateMusic(prompt: "dark piano", lyrics: "[Verse]\nHello\n[Chorus]\nWorld")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("upstream request sat idle for about 60 seconds"))
            XCTAssertTrue(error.localizedDescription.contains("32kHz and 128k"))
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }

    func testGenerateMusicWithoutLyricsUsesLyricsOptimizerAndReturnsURL() async throws {
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            XCTAssertEqual(request.httpMethod, "POST")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            XCTAssertEqual(bodyObject["model"] as? String, MiniMaxSettingsStore.shared.musicModel)
            XCTAssertEqual(bodyObject["output_format"] as? String, "url")
            XCTAssertEqual(bodyObject["lyrics_optimizer"] as? Bool, true)
            XCTAssertNil(bodyObject["lyrics"])

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "https://example.com/generated.mp3",
                    "status": 2,
                ],
                "trace_id": "trace-456",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateMusic(prompt: "folk song", lyrics: nil)

        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated.mp3")
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicWithEmptyLyricsUsesLyricsOptimizer() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            XCTAssertEqual(bodyObject["lyrics_optimizer"] as? Bool, true)
            XCTAssertNil(bodyObject["lyrics"])
            XCTAssertNil(bodyObject["is_instrumental"])

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "https://example.com/generated-no-lyrics.mp3",
                    "status": 2,
                ],
                "trace_id": "trace-789",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateMusic(prompt: "ambient track", lyrics: "")

        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated-no-lyrics.mp3")
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicDoesNotQueryLegacyMusicStatusEndpoint() async throws {
        var receivedPaths: [String] = []

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            receivedPaths.append(path)

            if path == "/v1/music_generation" {
                let responseBody: [String: Any] = [
                    "data": [
                        "status": 1
                    ],
                    "trace_id": "trace-pending",
                    "base_resp": [
                        "status_code": 0,
                        "status_msg": "success",
                    ],
                ]

                let responseData = try JSONSerialization.data(withJSONObject: responseBody)
                let response = try XCTUnwrap(
                    HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
                )
                return (response, responseData)
            }

            XCTFail("Unexpected legacy query path: \(path)")
            throw URLError(.badURL)
        }

        do {
            _ = try await miniMaxClient.generateMusic(prompt: "folk song", lyrics: nil)
            XCTFail("Expected generateMusic to fail when music API does not return audio payload")
        } catch {
            XCTAssertEqual(receivedPaths, ["/v1/music_generation"])
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }
}

#if canImport(AppKit)
extension CodeToolTests {
    func testImageImportSupportNormalizationPrefersPNGData() throws {
        let asset = try ImageImportSupport.importAsset(
            from: Self.tinyPNGData,
            suggestedFileName: "portrait.jpeg"
        )

        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(asset.fileName, "portrait.png")
        XCTAssertEqual(asset.sizeBytes, asset.pngData.count)
        XCTAssertEqual(Array(asset.pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertTrue(ImageImportSupport.dataURI(for: asset).hasPrefix("data:image/png;base64,"))
    }
}
#endif