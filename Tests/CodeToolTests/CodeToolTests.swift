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
        super.tearDown()
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
    }
}
