import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

private final class ClaudeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ClaudeCLIEvent] = []

    func append(_ event: ClaudeCLIEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [ClaudeCLIEvent] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}

extension CodeToolTests {
    func testClaudeChatHistoryRecordCodable() throws {
        let record = ClaudeChatHistoryRecord(
            workingDirectory: "/tmp/demo-project",
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

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[1].thinkingContent, "User says hello")
        XCTAssertEqual(decoded.totalCostUSD, 0.05)
        XCTAssertEqual(decoded.workingDirectory, "/tmp/demo-project")
    }

    func testClaudeChatHistoryRecordCodableBackwardCompatibilityWithoutWorkingDirectory() throws {
        let json = """
        {
          "id": "B3B7B6A9-7A7F-42D2-8D54-CA8E77F594B1",
          "createdAt": "2026-04-03T00:00:00Z",
          "messages": [
            {
              "role": "user",
              "content": "Hello"
            }
          ],
          "model": "claude-sonnet-4-20250514",
          "referenceID": "test-ref"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: Data(json.utf8))

        XCTAssertNil(decoded.workingDirectory)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.model, "claude-sonnet-4-20250514")
    }

    func testClaudeCLIClientUsesResumeForExistingSession() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude.sh")
        let argsLogURL = tempDirectory.appendingPathComponent("claude-args.log")

        let script = """
        #!/bin/zsh
        print -rl -- \"$@\" > \"$CODETOOL_CLAUDE_ARGS_LOG\"
        print '{"type":"system","subtype":"init","session_id":"8f600fbd-4226-4700-8a30-6988f438c595","model":"claude-sonnet-4-20250514"}'
        print '{"type":"result","is_error":false,"total_cost_usd":0,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1},"session_id":"8f600fbd-4226-4700-8a30-6988f438c595"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        setenv("CODETOOL_CLAUDE_ARGS_LOG", argsLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_ARGS_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "你好",
            settings: store,
            sessionId: "4cde10f7-cc71-4d25-8472-f9737d911dc8",
            workingDirectory: tempDirectory.path
        ) { _ in }

        let args = try String(contentsOf: argsLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        XCTAssertTrue(args.contains("--resume"))
        XCTAssertFalse(args.contains("--session-id"))
        let resumeIndex = try XCTUnwrap(args.firstIndex(of: "--resume"))
        XCTAssertEqual(args[resumeIndex + 1], "4cde10f7-cc71-4d25-8472-f9737d911dc8")
    }

    func testClaudeCLIClientUsesConfiguredPermissionMode() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude-permissions.sh")
        let argsLogURL = tempDirectory.appendingPathComponent("claude-permissions-args.log")

        let script = """
        #!/bin/zsh
        print -rl -- \"$@\" > \"$CODETOOL_CLAUDE_ARGS_LOG\"
        print '{"type":"system","subtype":"init","session_id":"permission-session","model":"claude-sonnet-4-20250514"}'
        print '{"type":"result","is_error":false,"total_cost_usd":0,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1},"session_id":"permission-session"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        setenv("CODETOOL_CLAUDE_ARGS_LOG", argsLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_ARGS_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.permissionMode = .auto
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "search the web",
            settings: store,
            sessionId: nil,
            workingDirectory: tempDirectory.path
        ) { _ in }

        let args = try String(contentsOf: argsLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let permissionModeIndex = try XCTUnwrap(args.firstIndex(of: "--permission-mode"))
        XCTAssertEqual(args[permissionModeIndex + 1], "auto")
    }

    func testClaudeCLIClientEmitsToolResultFromStreamEvent() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude-tool-result.sh")

        let script = """
        #!/bin/zsh
        print '{"type":"system","subtype":"init","session_id":"tool-session","model":"claude-sonnet-4-20250514"}'
        print '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_123","name":"mcp_jina_search_web","input":{}}}}'
        print '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":\\"latest chapter\\"}"}}}'
        print '{"type":"stream_event","event":{"type":"content_block_stop","index":0}}'
        print '{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_result","tool_use_id":"toolu_123","content":"search results"}}}'
        print '{"type":"stream_event","event":{"type":"content_block_stop","index":1}}'
        print '{"type":"result","is_error":false,"total_cost_usd":0,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1},"session_id":"tool-session"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        let recorder = ClaudeEventRecorder()

        await client.send(
            message: "find something",
            settings: store,
            sessionId: nil,
            workingDirectory: tempDirectory.path
        ) { event in
            recorder.append(event)
        }

        let receivedEvents = recorder.events

        guard case .toolUseStart(let toolUseId, let toolName) = receivedEvents.first(where: {
            if case .toolUseStart = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected tool use start event")
        }
        XCTAssertEqual(toolUseId, "toolu_123")
        XCTAssertEqual(toolName, "mcp_jina_search_web")

        guard case .toolResult(let resultToolUseId, let content) = receivedEvents.first(where: {
            if case .toolResult = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected tool result event")
        }
        XCTAssertEqual(resultToolUseId, "toolu_123")
        XCTAssertEqual(content, "search results")
    }

    func testClaudeCLIClientUsesExplicitWorkingDirectory() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude-working-dir.sh")
        let cwdLogURL = tempDirectory.appendingPathComponent("claude-cwd.log")
        let workingDirectoryURL = tempDirectory.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)

        let script = """
        #!/bin/zsh
        print -r -- "$PWD" > "$CODETOOL_CLAUDE_CWD_LOG"
        print '{"type":"system","subtype":"init","session_id":"working-dir-session","model":"claude-sonnet-4-20250514"}'
        print '{"type":"result","is_error":false,"total_cost_usd":0,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1},"session_id":"working-dir-session"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        setenv("CODETOOL_CLAUDE_CWD_LOG", cwdLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_CWD_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "pwd",
            settings: store,
            sessionId: nil,
            workingDirectory: workingDirectoryURL.path
        ) { _ in }

        let cwd = try String(contentsOf: cwdLogURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(
            URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path,
            workingDirectoryURL.resolvingSymlinksInPath().path
        )
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

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.messages.count, 1)
        let decodedAttachments = try XCTUnwrap(decoded.messages.first?.attachments)
        XCTAssertEqual(decodedAttachments.count, 1)
        XCTAssertEqual(decodedAttachments.first?.fileName, "abc-photo.png")
        XCTAssertEqual(decodedAttachments.first?.mimeType, "image/png")
        XCTAssertEqual(decodedAttachments.first?.sizeBytes, 12345)
        XCTAssertEqual(decodedAttachments.first?.type, "image")
    }

    func testClaudeChatAttachmentRecordCodableBackwardCompatibility() throws {
        let json = """
        {
            "role": "user",
            "content": "Hello"
        }
        """

        let decoded = try JSONDecoder().decode(ClaudeChatMessageRecord.self, from: Data(json.utf8))

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

    func testBuildOutgoingPromptFallbacksWithoutInlineText() {
        let plainPrompt = ClaudeChatView.buildOutgoingPrompt(text: "Just a question", imagePaths: [])
        XCTAssertEqual(plainPrompt, "Just a question")
        XCTAssertFalse(plainPrompt.contains("Attached images:"))

        let imageOnlyPrompt = ClaudeChatView.buildOutgoingPrompt(text: "", imagePaths: ["/tmp/img.png"])
        XCTAssertTrue(imageOnlyPrompt.contains("Attached images:"))
        XCTAssertTrue(imageOnlyPrompt.contains("- /tmp/img.png"))
        XCTAssertTrue(imageOnlyPrompt.contains("Please describe and analyze the attached image(s)."))
    }

    func testClaudeMarkdownDocumentParsesTablesTaskListsAndStrikethrough() {
        let markdown = """
        ## Summary

        - [x] shipped
        - [ ] pending
        - ~~deprecated~~

        | Name | Value |
        | :--- | ---: |
        | Alpha | 1 |
        """

        let document = ClaudeMarkdownDocumentModel(markdown: markdown)

        XCTAssertEqual(document.blocks.count, 3)

        guard case let .heading(level, text) = document.blocks[0] else {
            return XCTFail("Expected a heading block")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "Summary")

        guard case let .unorderedList(items) = document.blocks[1] else {
            return XCTFail("Expected an unordered list block")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].checkbox, .checked)
        XCTAssertEqual(items[1].checkbox, .unchecked)
        XCTAssertNil(items[2].checkbox)

        guard case let .paragraph(firstItemMarkdown) = items[0].blocks[0] else {
            return XCTFail("Expected list item paragraph")
        }
        XCTAssertEqual(firstItemMarkdown, "shipped")

        guard case let .paragraph(strikethroughMarkdown) = items[2].blocks[0] else {
            return XCTFail("Expected strikethrough paragraph")
        }
        XCTAssertEqual(strikethroughMarkdown, "~~deprecated~~")

        guard case let .table(header, rows) = document.blocks[2] else {
            return XCTFail("Expected a table block")
        }
        XCTAssertEqual(header.count, 2)
        XCTAssertEqual(header[0].markdown, "Name")
        XCTAssertEqual(header[0].alignment, .left)
        XCTAssertEqual(header[1].markdown, "Value")
        XCTAssertEqual(header[1].alignment, .right)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.markdown), ["Alpha", "1"])
    }

    func testClaudeMarkdownDocumentParsesQuotesAndCodeBlocks() {
        let markdown = """
        > Keep this note handy.

        ```swift
        let value = 42
        ```
        """

        let document = ClaudeMarkdownDocumentModel(markdown: markdown)

        XCTAssertEqual(document.blocks.count, 2)

        guard case let .quote(quoteBlocks) = document.blocks[0] else {
            return XCTFail("Expected a quote block")
        }
        XCTAssertEqual(quoteBlocks.count, 1)
        guard case let .paragraph(quoteMarkdown) = quoteBlocks[0] else {
            return XCTFail("Expected quote paragraph content")
        }
        XCTAssertEqual(quoteMarkdown, "Keep this note handy.")

        guard case let .codeBlock(language, code) = document.blocks[1] else {
            return XCTFail("Expected a code block")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let value = 42")
    }

    func testClaudeChatHistoryRecordPreservesRawMarkdownContent() throws {
        let markdown = """
        Use ~~old~~ **new**

        | A | B |
        | - | - |
        | 1 | 2 |
        """

        let record = ClaudeChatHistoryRecord(
            messages: [ClaudeChatMessageRecord(role: "assistant", content: markdown)],
            model: "claude-sonnet-4-20250514",
            referenceID: "markdown-history-ref"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.messages.first?.content, markdown)
    }

    func testClaudeChatViewPlaceholderStaysHiddenWhileDraftTextIsVisible() {
        XCTAssertFalse(
            ClaudeChatView.shouldShowComposerPlaceholder(
                inputText: "",
                hasVisibleDraftText: true,
                hasImages: false
            )
        )
        XCTAssertTrue(
            ClaudeChatView.shouldShowComposerPlaceholder(
                inputText: "",
                hasVisibleDraftText: false,
                hasImages: false
            )
        )
    }

    func testClaudeConversationRenderStateIgnoresDraftChanges() {
        let base = ClaudeConversationRenderState.make(
            isStreaming: false,
            workingDirectoryTitle: "repo",
            hasSystemPrompt: false,
            composerImageCount: 0,
            draftText: "",
            hasVisibleDraftText: false,
            isToolVisible: true,
            streamingScrollRevision: 0
        )

        let draftChanged = ClaudeConversationRenderState.make(
            isStreaming: false,
            workingDirectoryTitle: "repo",
            hasSystemPrompt: false,
            composerImageCount: 0,
            draftText: "hello",
            hasVisibleDraftText: true,
            isToolVisible: true,
            streamingScrollRevision: 0
        )

        XCTAssertEqual(base, draftChanged)
    }

    func testClaudeConversationRenderStateTracksConversationChanges() {
        let base = ClaudeConversationRenderState.make(
            isStreaming: false,
            workingDirectoryTitle: "repo",
            hasSystemPrompt: false,
            composerImageCount: 0,
            draftText: "",
            hasVisibleDraftText: false,
            isToolVisible: true,
            streamingScrollRevision: 0
        )

        let updated = ClaudeConversationRenderState.make(
            isStreaming: true,
            workingDirectoryTitle: "repo",
            hasSystemPrompt: false,
            composerImageCount: 0,
            draftText: "",
            hasVisibleDraftText: false,
            isToolVisible: true,
            streamingScrollRevision: 1
        )

        XCTAssertNotEqual(base, updated)
    }
}