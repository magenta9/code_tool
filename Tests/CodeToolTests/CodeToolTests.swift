import Foundation
import XCTest

@testable import CodeToolCore

#if canImport(SwiftUI)
    import SwiftUI
#endif

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class CodeToolTests: XCTestCase {
    // MARK: - Tool model tests

    func testToolInitialization() {
        let tool = Tool(name: "Test Tool", description: "A test.", systemImage: "star")
        XCTAssertFalse(tool.id.uuidString.isEmpty)
        XCTAssertEqual(tool.name, "Test Tool")
        XCTAssertEqual(tool.description, "A test.")
        XCTAssertEqual(tool.systemImage, "star")
    }

    func testToolHashable() {
        let tool1 = Tool(name: "A", description: "A", systemImage: "a")
        let tool2 = Tool(name: "A", description: "A", systemImage: "a")
        // Different UUIDs mean they are not equal
        XCTAssertNotEqual(tool1, tool2)
        let set: Set<Tool> = [tool1, tool2]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - ToolRegistry tests

    private var savedDefaults: [Tool] = []
    private var savedConfig: MiniMaxConfig = .defaults
    private var savedClaudePath = ""
    private var savedClaudeAPIKey = ""
    private var savedClaudeModel = ""
    private var savedClaudeSystemPrompt = ""
    private var savedClaudeMaxTurns = 10
    private var savedClaudeMaxBudgetUSD = 5.0
    private var savedClaudeUseBare = true
    private var savedClaudeWorkingDirectory = ""
    private var temporaryLogDirectoryURL: URL?

    override func setUp() {
        super.setUp()
        savedDefaults = ToolRegistry.defaults

        let store = MiniMaxSettingsStore.shared
        savedConfig = store.currentConfig

        let claudeStore = ClaudeCLISettingsStore.shared
        savedClaudePath = claudeStore.claudePath
        savedClaudeAPIKey = claudeStore.apiKey
        savedClaudeModel = claudeStore.model
        savedClaudeSystemPrompt = claudeStore.systemPrompt
        savedClaudeMaxTurns = claudeStore.maxTurns
        savedClaudeMaxBudgetUSD = claudeStore.maxBudgetUSD
        savedClaudeUseBare = claudeStore.useBare
        savedClaudeWorkingDirectory = claudeStore.workingDirectory

        store.apiKey = "test-api-key"
        store.baseURL = "https://example.com/v1"

        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil

        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeToolTests-\(UUID().uuidString)", isDirectory: true)
        temporaryLogDirectoryURL = tempDirectoryURL
        try? FileManager.default.createDirectory(
            at: tempDirectoryURL, withIntermediateDirectories: true)

        let setupExpectation = expectation(description: "configure log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(tempDirectoryURL)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 2.0)
    }

    override func tearDown() {
        ToolRegistry.defaults = savedDefaults

        let store = MiniMaxSettingsStore.shared
        store.apiKey = savedConfig.apiKey
        store.baseURL = savedConfig.baseURL
        store.chatModel = savedConfig.chatModel
        store.speechModel = savedConfig.speechModel
        store.imageModel = savedConfig.imageModel
        store.musicModel = savedConfig.musicModel

        let claudeStore = ClaudeCLISettingsStore.shared
        claudeStore.claudePath = savedClaudePath
        claudeStore.apiKey = savedClaudeAPIKey
        claudeStore.model = savedClaudeModel
        claudeStore.systemPrompt = savedClaudeSystemPrompt
        claudeStore.maxTurns = savedClaudeMaxTurns
        claudeStore.maxBudgetUSD = savedClaudeMaxBudgetUSD
        claudeStore.useBare = savedClaudeUseBare
        claudeStore.workingDirectory = savedClaudeWorkingDirectory
        claudeStore.discoverCLI()

        MockURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)

        let resetExpectation = expectation(description: "reset log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(nil)
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 2.0)

        if let temporaryLogDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryLogDirectoryURL)
        }

        super.tearDown()
    }

    private func logContent(for category: AppLogCategory) async throws -> String {
        let logFiles = await AppLogger.shared.logFileURLs(for: category)
        XCTAssertEqual(logFiles.count, 1)

        let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        return try XCTUnwrap(String(data: logData, encoding: .utf8))
    }

    func testRegistryDefaultsNotEmpty() {
        XCTAssertFalse(ToolRegistry.defaults.isEmpty)
    }

    func testRegistryContainsTenTools() {
        XCTAssertEqual(ToolRegistry.defaults.count, 10)
    }

    func testRegistryDefaultNamesAreUnique() {
        let names = ToolRegistry.defaults.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count)
    }

    func testRegistryContainsExpectedTools() {
        let names = Set(ToolRegistry.defaults.map(\.name))
        let expected: Set<String> = [
            "JSON Tool", "Image Converter", "JSON Diff",
            "Timestamp Converter", "JWT Tool", "Word Cloud",
            "AI Chat", "AI Speech", "AI Image", "AI Music",
        ]
        XCTAssertEqual(names, expected)
    }

    func testRegistryCanRegisterAdditionalTool() {
        let originalCount = ToolRegistry.defaults.count
        let extra = Tool(name: "Extra Tool", description: "Extra.", systemImage: "star")
        ToolRegistry.defaults.append(extra)
        XCTAssertEqual(ToolRegistry.defaults.count, originalCount + 1)
    }

    func testClaudeCLISettingsStoreDefaults() {
        let store = ClaudeCLISettingsStore.shared
        store.resetToDefaults()

        XCTAssertEqual(store.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(store.maxTurns, 10)
        XCTAssertEqual(store.maxBudgetUSD, 5.0)
        XCTAssertTrue(store.useBare)
    }

    func testClaudeChatHistoryRecordCodable() throws {
        let record = ClaudeChatHistoryRecord(
            messages: [
                ClaudeChatMessageRecord(role: "user", content: "Hello"),
                ClaudeChatMessageRecord(
                    role: "assistant",
                    content: "Hi",
                    thinkingContent: "User says hello"
                ),
            ],
            model: "claude-sonnet-4-20250514",
            totalCostUSD: 0.05,
            inputTokens: 100,
            outputTokens: 10,
            referenceID: "test-ref"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[1].thinkingContent, "User says hello")
        XCTAssertEqual(decoded.totalCostUSD, 0.05)
    }

    func testClaudeCLIClientUsesResumeForExistingSession() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude.sh")
        let argsLogURL = tempDirectory.appendingPathComponent("claude-args.log")

        let script = """
        #!/bin/zsh
        print -rl -- \"$@\" > \"$CODETOOL_CLAUDE_ARGS_LOG\"
        print '{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"8f600fbd-4226-4700-8a30-6988f438c595\",\"model\":\"claude-sonnet-4-20250514\"}'
        print '{\"type\":\"result\",\"is_error\":false,\"total_cost_usd\":0,\"duration_ms\":1,\"usage\":{\"input_tokens\":1,\"output_tokens\":1},\"session_id\":\"8f600fbd-4226-4700-8a30-6988f438c595\"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        setenv("CODETOOL_CLAUDE_ARGS_LOG", argsLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_ARGS_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "你好",
            settings: store,
            sessionId: "4cde10f7-cc71-4d25-8472-f9737d911dc8"
        ) { _ in }

        let argsText = try String(contentsOf: argsLogURL, encoding: .utf8)
        let args = argsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        XCTAssertTrue(args.contains("--resume"))
        XCTAssertFalse(args.contains("--session-id"))
        let resumeIndex = try XCTUnwrap(args.firstIndex(of: "--resume"))
        XCTAssertEqual(args[resumeIndex + 1], "4cde10f7-cc71-4d25-8472-f9737d911dc8")
    }

    func testToolViewCacheRetainsVisitedToolsInSelectionOrder() {
        var retainedToolNames: [String] = []

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: "JSON Tool"
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool"])

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: "Image Converter"
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool", "Image Converter"])

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: "JSON Tool"
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool", "Image Converter"])

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: nil
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool", "Image Converter"])
    }

    #if canImport(SwiftUI)
        func testContentViewDoesNotUseNavigationSplitView() {
            let bodyTypeDescription = String(describing: type(of: ContentView().body))
            XCTAssertFalse(bodyTypeDescription.contains("NavigationSplitView"))
        }
    #endif

    func testTextToSpeechRequestsHexOutputAndDecodesHexAudio() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/t2a_v2")

            let bodyData = try XCTUnwrap(request.httpBody)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
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
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await MiniMaxAPIClient.shared.textToSpeech(text: "Hello")

        XCTAssertEqual(response.audioData, Data("Hello".utf8))
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.durationMs, 321)
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testTextToSpeechTimeoutWritesStructuredErrorLog() async throws {
        let sensitiveText = "private speech text"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/t2a_v2")
            throw URLError(.timedOut)
        }

        do {
            _ = try await MiniMaxAPIClient.shared.textToSpeech(text: sensitiveText)
            XCTFail("Expected textToSpeech to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logContent = try await logContent(for: .aispeech)
            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("request_failed"))
            XCTAssertTrue(logContent.contains("request_text_to_speech"))
            XCTAssertTrue(logContent.contains("NSURLErrorDomain"))
            XCTAssertFalse(logContent.contains(sensitiveText))
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
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 500, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        do {
            _ = try await MiniMaxAPIClient.shared.generateImage(prompt: sensitivePrompt)
            XCTFail("Expected generateImage to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logContent = try await logContent(for: .aiimage)
            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("request_failed"))
            XCTAssertTrue(logContent.contains("request_image_generation"))
            XCTAssertTrue(logContent.contains("4001"))
            XCTAssertFalse(logContent.contains(sensitivePrompt))
        }
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
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        do {
            try await MiniMaxAPIClient.shared.chatCompletionStream(
                messages: [MiniMaxAPIClient.ChatMessage(role: "user", content: sensitivePrompt)],
                referenceID: referenceID
            ) { _ in }
            XCTFail("Expected chatCompletionStream to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID: \(referenceID)"))

            let logContent = try await logContent(for: .aichat)
            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("request_failed"))
            XCTAssertTrue(logContent.contains("stream_chat_completion"))
            XCTAssertTrue(logContent.contains(referenceID))
            XCTAssertFalse(logContent.contains(sensitivePrompt))
        }
    }

    func testGenerateMusicWithLyricsUsesURLTransportAndParsesAudioURL() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let bodyData = try XCTUnwrap(request.httpBody)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
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
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await MiniMaxAPIClient.shared.generateMusic(
            prompt: "folk song",
            lyrics: "[Verse]\nHello world"
        )

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
            _ = try await MiniMaxAPIClient.shared.generateMusic(
                prompt: "slow orchestral soundtrack")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logFiles = await AppLogger.shared.logFileURLs(for: .aimusic)
            XCTAssertEqual(logFiles.count, 1)

            let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
            let logContent = try XCTUnwrap(String(data: logData, encoding: .utf8))

            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("music_request_failed"))
            XCTAssertTrue(logContent.contains("request_music_generation"))
            XCTAssertTrue(logContent.contains("NSURLErrorDomain"))
            XCTAssertTrue(logContent.contains("-1001"))
            XCTAssertTrue(logContent.contains("stackTrace"))
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
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        do {
            _ = try await MiniMaxAPIClient.shared.generateMusic(prompt: "dark piano")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "Current MiniMax token plan does not support the configured music model."))
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
            _ = try await MiniMaxAPIClient.shared.generateMusic(
                prompt: "dark piano", lyrics: "[Verse]\nHello\n[Chorus]\nWorld")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "upstream request sat idle for about 60 seconds"))
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

            let bodyData = try XCTUnwrap(request.httpBody)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

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
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await MiniMaxAPIClient.shared.generateMusic(
            prompt: "folk song", lyrics: nil)

        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated.mp3")
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
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                        headerFields: nil))
                return (response, responseData)
            }

            XCTFail("Unexpected legacy query path: \(path)")
            throw URLError(.badURL)
        }

        do {
            _ = try await MiniMaxAPIClient.shared.generateMusic(prompt: "folk song", lyrics: nil)
            XCTFail("Expected generateMusic to fail when music API does not return audio payload")
        } catch {
            XCTAssertEqual(receivedPaths, ["/v1/music_generation"])
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }

    // MARK: - Claude CLI Optimization Tests

    func testClaudeChatConversationRecordReusesStableID() async throws {
        let stableID = UUID()
        let stableCreatedAt = Date()

        let record1 = ClaudeChatHistoryRecord(
            id: stableID,
            createdAt: stableCreatedAt,
            messages: [
                ClaudeChatMessageRecord(role: "user", content: "Hello")
            ],
            model: "claude-sonnet-4-20250514",
            referenceID: "ref-1"
        )

        let record2 = ClaudeChatHistoryRecord(
            id: stableID,
            createdAt: stableCreatedAt,
            messages: [
                ClaudeChatMessageRecord(role: "user", content: "Hello"),
                ClaudeChatMessageRecord(role: "assistant", content: "Hi there"),
                ClaudeChatMessageRecord(role: "user", content: "How are you?"),
            ],
            model: "claude-sonnet-4-20250514",
            totalCostUSD: 0.01,
            referenceID: "ref-2"
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer {
            Task { await HistoryStore.shared.setBaseURLForTesting(nil) }
        }

        // Save first version
        try await HistoryStore.shared.save(record1)
        var records: [ClaudeChatHistoryRecord] = try await HistoryStore.shared.listClaudeChat()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.messages.count, 1)

        // Save updated version with same ID — should overwrite, not create second file
        try await HistoryStore.shared.save(record2)
        records = try await HistoryStore.shared.listClaudeChat()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.messages.count, 3)
        XCTAssertEqual(records.first?.id, stableID)
        XCTAssertEqual(records.first?.totalCostUSD, 0.01)
    }

    func testClaudeChatAttachmentRecordCodable() throws {
        let attachment = ClaudeChatAttachmentRecord(
            type: "image",
            fileName: "abc-photo.png",
            mimeType: "image/png",
            sizeBytes: 12345
        )

        let message = ClaudeChatMessageRecord(
            role: "user",
            content: "Check this image",
            attachments: [attachment]
        )

        let record = ClaudeChatHistoryRecord(
            messages: [message],
            model: "claude-sonnet-4-20250514",
            referenceID: "test-attachment-ref"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.messages.count, 1)
        let decodedAttachments = try XCTUnwrap(decoded.messages.first?.attachments)
        XCTAssertEqual(decodedAttachments.count, 1)
        XCTAssertEqual(decodedAttachments.first?.fileName, "abc-photo.png")
        XCTAssertEqual(decodedAttachments.first?.mimeType, "image/png")
        XCTAssertEqual(decodedAttachments.first?.sizeBytes, 12345)
        XCTAssertEqual(decodedAttachments.first?.type, "image")
    }

    func testClaudeChatAttachmentRecordCodableBackwardCompatibility() throws {
        // Ensure records without attachments still decode (backward compat)
        let json = """
        {
            "role": "user",
            "content": "Hello"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeChatMessageRecord.self, from: data)

        XCTAssertEqual(decoded.role, "user")
        XCTAssertEqual(decoded.content, "Hello")
        XCTAssertNil(decoded.attachments)
    }

    func testBuildOutgoingPromptIncludesImagePaths() {
        let paths = ["/tmp/image1.png", "/tmp/image2.jpg"]
        let prompt = ClaudeChatView.buildOutgoingPrompt(text: "Describe these", imagePaths: paths)

        XCTAssertTrue(prompt.contains("Attached images:"))
        XCTAssertTrue(prompt.contains("- /tmp/image1.png"))
        XCTAssertTrue(prompt.contains("- /tmp/image2.jpg"))
        XCTAssertTrue(prompt.contains("User request:"))
        XCTAssertTrue(prompt.contains("Describe these"))
    }

    func testBuildOutgoingPromptWithoutImages() {
        let prompt = ClaudeChatView.buildOutgoingPrompt(text: "Just a question", imagePaths: [])
        XCTAssertEqual(prompt, "Just a question")
        XCTAssertFalse(prompt.contains("Attached images:"))
    }

    func testBuildOutgoingPromptImageOnlyUsesBootstrapText() {
        let prompt = ClaudeChatView.buildOutgoingPrompt(text: "", imagePaths: ["/tmp/img.png"])
        XCTAssertTrue(prompt.contains("Attached images:"))
        XCTAssertTrue(prompt.contains("- /tmp/img.png"))
        XCTAssertTrue(prompt.contains("Please describe and analyze the attached image(s)."))
    }

    #if canImport(AppKit)
        func testClaudeChatComposerConfiguresBothDelegates() {
            var text = ""
            let composer = ClaudeChatComposer(
                text: Binding(
                    get: { text },
                    set: { text = $0 }
                ),
                isStreaming: false,
                onSubmit: {},
                onPasteImages: { _ in },
                onEscape: {}
            )
            let coordinator = composer.makeCoordinator()
            let textView = ComposerTextView()

            ClaudeChatComposer.configureTextView(textView, coordinator: coordinator)

            XCTAssertTrue(textView.delegate === coordinator)
            XCTAssertTrue(textView.composerDelegate === coordinator)
        }
    #endif
}
