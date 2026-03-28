import XCTest
@testable import CodeToolCore
import Foundation

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
    private var savedAPIKey = ""
    private var savedBaseURL = ""
    private var savedChatModel = ""
    private var savedSpeechModel = ""
    private var savedImageModel = ""
    private var savedMusicModel = ""
    private var temporaryLogDirectoryURL: URL?

    override func setUp() {
        super.setUp()
        savedDefaults = ToolRegistry.defaults

        let provider = MiniMaxProvider.shared
        savedAPIKey = provider.apiKey
        savedBaseURL = provider.baseURL
        savedChatModel = provider.chatModel
        savedSpeechModel = provider.speechModel
        savedImageModel = provider.imageModel
        savedMusicModel = provider.musicModel

        provider.apiKey = "test-api-key"
        provider.baseURL = "https://example.com/v1"

        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil

        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeToolTests-\(UUID().uuidString)", isDirectory: true)
        temporaryLogDirectoryURL = tempDirectoryURL
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let setupExpectation = expectation(description: "configure log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(tempDirectoryURL)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 2.0)
    }

    override func tearDown() {
        ToolRegistry.defaults = savedDefaults

        let provider = MiniMaxProvider.shared
        provider.apiKey = savedAPIKey
        provider.baseURL = savedBaseURL
        provider.chatModel = savedChatModel
        provider.speechModel = savedSpeechModel
        provider.imageModel = savedImageModel
        provider.musicModel = savedMusicModel

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

    func testRegistryContainsElevenTools() {
        XCTAssertEqual(ToolRegistry.defaults.count, 11)
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
            "MiniMax Settings"
        ]
        XCTAssertEqual(names, expected)
    }

    func testRegistryCanRegisterAdditionalTool() {
        let originalCount = ToolRegistry.defaults.count
        let extra = Tool(name: "Extra Tool", description: "Extra.", systemImage: "star")
        ToolRegistry.defaults.append(extra)
        XCTAssertEqual(ToolRegistry.defaults.count, originalCount + 1)
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
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(bodyObject["output_format"] as? String, "hex")

            let audioSetting = try XCTUnwrap(bodyObject["audio_setting"] as? [String: Any])
            XCTAssertEqual(audioSetting["format"] as? String, "mp3")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success"
                ],
                "data": [
                    "audio": "48656c6c6f"
                ],
                "extra_info": [
                    "audio_length": 321
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
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
                    "status_msg": "invalid prompt"
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 500, httpVersion: nil, headerFields: nil))
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
                    "status_msg": "rate limited"
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil, headerFields: nil))
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

    func testGenerateMusicRequestsHexOutputAndDecodesInlineAudio() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let bodyData = try XCTUnwrap(request.httpBody)
            let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(bodyObject["output_format"] as? String, "hex")

            let audioSetting = try XCTUnwrap(bodyObject["audio_setting"] as? [String: Any])
            XCTAssertEqual(audioSetting["sample_rate"] as? Int, 44100)
            XCTAssertEqual(audioSetting["bitrate"] as? Int, 256000)
            XCTAssertEqual(audioSetting["format"] as? String, "mp3")

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "48656c6c6f",
                    "status": 2
                ],
                "trace_id": "trace-123",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success"
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, responseData)
        }

        let response = try await MiniMaxAPIClient.shared.generateMusic(prompt: "folk song")

        XCTAssertEqual(response.audioData, Data("Hello".utf8))
        XCTAssertNil(response.audioURL)
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicTimeoutWritesStructuredErrorLog() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            throw URLError(.timedOut)
        }

        do {
            _ = try await MiniMaxAPIClient.shared.generateMusic(prompt: "slow orchestral soundtrack")
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
}
