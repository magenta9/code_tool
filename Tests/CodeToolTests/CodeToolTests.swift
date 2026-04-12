import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation
@testable import CodeToolUI

final class MockURLProtocol: URLProtocol {
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

final class MockWebSocket: MiniMaxWebSocketing {
    private(set) var sentPayloads: [String] = []
    private var receivedMessages: [URLSessionWebSocketTask.Message]
    private(set) var closeCode: URLSessionWebSocketTask.CloseCode?
    private(set) var closeReason: Data?

    init(receivedMessages: [URLSessionWebSocketTask.Message]) {
        self.receivedMessages = receivedMessages
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        switch message {
        case .string(let payload):
            sentPayloads.append(payload)
        case .data(let payload):
            sentPayloads.append(String(data: payload, encoding: .utf8) ?? "")
        @unknown default:
            throw URLError(.cannotDecodeRawData)
        }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard !receivedMessages.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return receivedMessages.removeFirst()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.closeCode = closeCode
        closeReason = reason
    }

    func sentJSONObject(at index: Int) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(sentPayloads[index].utf8)) as? [String: Any]
        )
    }
}

final class CodeToolTests: XCTestCase {
    var miniMaxClient: MiniMaxAPIClient!
    var savedDefaults: [Tool] = []
    var savedConfig: MiniMaxConfig = .defaults
    var temporaryLogDirectoryURL: URL?
    var temporaryDiagnosticsDirectoryURL: URL?
    let asyncLogPropagationDelay: UInt64 = 300_000_000

    override func setUp() {
        super.setUp()
        savedDefaults = ToolRegistry.defaults

        let store = MiniMaxSettingsStore.shared
        savedConfig = store.currentConfig

        store.apiKey = "test-api-key"
        store.baseURL = "https://example.com/v1"

        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        miniMaxClient = MiniMaxAPIClient.makeTestingClient(urlProtocolType: MockURLProtocol.self)

        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeToolTests-\(UUID().uuidString)", isDirectory: true)
        temporaryLogDirectoryURL = tempDirectoryURL
        try? FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )

        let tempDiagnosticsDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeToolDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDiagnosticsDirectoryURL = tempDiagnosticsDirectoryURL
        try? FileManager.default.createDirectory(
            at: tempDiagnosticsDirectoryURL,
            withIntermediateDirectories: true
        )

        let setupExpectation = expectation(description: "configure log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(tempDirectoryURL)
            await DiagnosticsStore.shared.setBaseURLForTesting(tempDiagnosticsDirectoryURL)
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

        MockURLProtocol.requestHandler = nil
        miniMaxClient = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)

        let resetExpectation = expectation(description: "reset log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(nil)
            await DiagnosticsStore.shared.setBaseURLForTesting(nil)
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 2.0)

        if let temporaryLogDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryLogDirectoryURL)
        }
        if let temporaryDiagnosticsDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDiagnosticsDirectoryURL)
        }

        super.tearDown()
    }

    func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func logContent(for category: AppLogCategory) async throws -> String {
        let logFiles = await AppLogger.shared.logFileURLs(for: category)
        XCTAssertEqual(logFiles.count, 1)

        let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        return try XCTUnwrap(String(data: logData, encoding: .utf8))
    }

    func logEntries(for category: AppLogCategory) async throws -> [AppLogEntry] {
        let logFiles = await AppLogger.shared.logFileURLs(for: category)
        XCTAssertEqual(logFiles.count, 1)

        let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        let lines = try XCTUnwrap(String(data: logData, encoding: .utf8))
            .split(whereSeparator: \.isNewline)

        return try lines.map { line in
            try JSONDecoder().decode(AppLogEntry.self, from: Data(line.utf8))
        }
    }

    static func requestBodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            XCTFail("Expected request body data")
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }

    static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+kv0YAAAAASUVORK5CYII="
    static let tinyPNGData = Data(base64Encoded: tinyPNGBase64) ?? Data()
}
