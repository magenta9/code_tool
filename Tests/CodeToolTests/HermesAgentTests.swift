import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

final class HermesAgentTests: XCTestCase {
    func testHermesCapabilityMatrixParsesDocumentedFlags() {
        let snapshot = HermesCLIHelpSnapshot(
            versionOutput: "hermes 0.9.1",
            rootHelpOutput: """
            Usage: hermes [OPTIONS] COMMAND

              -p, --profile TEXT   Use a named profile
              -r, --resume TEXT    Resume a session
              -c, --continue       Continue the latest session
              -Q, --quiet          Only output the final response and session info
              -v, --verbose        Show progress events

            Commands:
              chat
              sessions
            """,
            chatHelpOutput: """
            Usage: hermes chat [OPTIONS]

              -q, --query TEXT     Run a one-shot query
              -m, --model TEXT     Override the model
                  --resume TEXT    Resume a session by ID
                  --continue       Continue the latest session
                  --provider TEXT  Override the provider

            Context references:
              @file:path/to/file.py
              @folder:path/to/project
            """,
            sessionsHelpOutput: """
            Usage: hermes sessions [OPTIONS] COMMAND

            Commands:
              list
              export
            """,
            sessionsListHelpOutput: """
            Usage: hermes sessions list [OPTIONS]

              --limit INTEGER
              --source TEXT
            """
        )

        let matrix = HermesCLIContractProbe.parseCapabilityMatrix(
            binaryPath: "/opt/homebrew/bin/hermes",
            snapshot: snapshot
        )

        XCTAssertEqual(matrix.binaryPath, "/opt/homebrew/bin/hermes")
        XCTAssertEqual(matrix.versionString, "0.9.1")
        XCTAssertTrue(matrix.supportsChatQuery)
        XCTAssertTrue(matrix.supportsQuietOutput)
        XCTAssertTrue(matrix.supportsResumeFlag)
        XCTAssertTrue(matrix.supportsContinueFlag)
        XCTAssertTrue(matrix.supportsSessionsList)
        XCTAssertTrue(matrix.supportsModelFlag)
        XCTAssertTrue(matrix.supportsProfileFlag)
        XCTAssertTrue(matrix.supportsContextReferences)
        XCTAssertEqual(matrix.outputMode, .finalTextOnly)
    }

    func testHermesCLIClientParsesQuietOutputSessionIDAndStripsMetadata() {
        let parsed = HermesCLIClient.parseQuietOutput(
            """
            ╭─ ⚕ Hermes ──────────────────────────────────────╮
            OK

            session_id: 20260407_173358_6bac01
            """
        )

        XCTAssertEqual(parsed.output, "OK")
        XCTAssertEqual(parsed.sessionID, "20260407_173358_6bac01")
    }

    func testHermesConversationRenderStateIgnoresDraftChanges() {
        let base = HermesConversationRenderState.make(
            composerAttachmentCount: 0,
            draftText: "",
            isToolVisible: true,
            streamingScrollRevision: 0
        )

        let draftChanged = HermesConversationRenderState.make(
            composerAttachmentCount: 0,
            draftText: "你好",
            isToolVisible: true,
            streamingScrollRevision: 0
        )

        XCTAssertEqual(base, draftChanged)
    }

    func testHermesConversationRenderStateTracksStreamingScrollChanges() {
        let base = HermesConversationRenderState.make(
            messages: [.user("hello")],
            composerAttachmentCount: 0,
            draftText: "",
            isToolVisible: true,
            streamingScrollRevision: 0
        )

        let updated = HermesConversationRenderState.make(
            messages: [.user("hello")],
            streamingText: "partial",
            composerAttachmentCount: 0,
            draftText: "",
            isToolVisible: true,
            streamingScrollRevision: 1
        )

        XCTAssertNotEqual(base, updated)
    }

    func testHermesCapabilityMatrixDefaultsToFinalTextOnlyWhenStreamingFlagsMissing() {
        let snapshot = HermesCLIHelpSnapshot(
            versionOutput: "hermes 0.9.1",
            rootHelpOutput: "Usage: hermes [OPTIONS] COMMAND\nCommands:\n  chat",
            chatHelpOutput: "Usage: hermes chat [OPTIONS]\n  -q, --query TEXT",
            sessionsHelpOutput: "Usage: hermes sessions [OPTIONS] COMMAND",
            sessionsListHelpOutput: nil
        )

        let matrix = HermesCLIContractProbe.parseCapabilityMatrix(
            binaryPath: "/tmp/hermes",
            snapshot: snapshot
        )

        XCTAssertTrue(matrix.supportsChatQuery)
        XCTAssertFalse(matrix.supportsQuietOutput)
        XCTAssertFalse(matrix.supportsSessionsList)
        XCTAssertEqual(matrix.outputMode, .finalTextOnly)
    }

    func testHermesPromptComposerUsesTypedContextReferencesAndBootstrapText() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesPromptComposer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: fileURL)

        let attachment = HermesAttachmentReference(
            fileURL: fileURL,
            displayName: "notes.txt",
            kindDescription: "text",
            sizeBytes: 5
        )

        let prompt = try HermesPromptComposer.compose(
            text: "",
            attachments: [attachment, attachment],
            capabilities: HermesCapabilityMatrix(
                binaryPath: "/tmp/hermes",
                versionString: "0.9.1",
                supportsChatQuery: true,
                supportsQuietOutput: true,
                supportsResumeFlag: true,
                supportsContinueFlag: true,
                supportsSessionsList: true,
                supportsModelFlag: true,
                supportsProfileFlag: true,
                supportsContextReferences: true,
                outputMode: .finalTextOnly
            )
        )

        XCTAssertTrue(prompt.contains("Please inspect the attached files."))
        XCTAssertTrue(prompt.contains("@file:\(fileURL.path)"))
        XCTAssertEqual(prompt.components(separatedBy: "@file:").count - 1, 1)
    }

    func testHermesPromptComposerRejectsMissingAttachments() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")
        let attachment = HermesAttachmentReference(
            fileURL: missingURL,
            displayName: missingURL.lastPathComponent,
            kindDescription: "text",
            sizeBytes: nil
        )

        XCTAssertThrowsError(
            try HermesPromptComposer.compose(
                text: "Inspect this",
                attachments: [attachment],
                capabilities: HermesCapabilityMatrix(
                    binaryPath: "/tmp/hermes",
                    versionString: "0.9.1",
                    supportsChatQuery: true,
                    supportsQuietOutput: true,
                    supportsResumeFlag: true,
                    supportsContinueFlag: true,
                    supportsSessionsList: true,
                    supportsModelFlag: true,
                    supportsProfileFlag: true,
                    supportsContextReferences: true,
                    outputMode: .finalTextOnly
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains(missingURL.lastPathComponent))
        }
    }

    func testHermesCLIClientBuildsQuietResumeCommandFromCapabilities() {
        let request = HermesTurnRequest(
            prompt: "Summarize the repo",
            resumeSessionID: "session-123",
            referenceID: "ref-123",
            modelOrProfile: "work",
            extraArguments: ["--unsafe-skip-confirmations"]
        )
        let capabilities = HermesCapabilityMatrix(
            binaryPath: "/opt/homebrew/bin/hermes",
            versionString: "0.9.1",
            supportsChatQuery: true,
            supportsQuietOutput: true,
            supportsResumeFlag: true,
            supportsContinueFlag: true,
            supportsSessionsList: true,
            supportsModelFlag: false,
            supportsProfileFlag: true,
            supportsContextReferences: true,
            outputMode: .finalTextOnly
        )

        let command = HermesCLIClient.makeCommand(request: request, capabilities: capabilities)

        XCTAssertEqual(command.executablePath, "/opt/homebrew/bin/hermes")
        XCTAssertEqual(
            command.arguments,
            [
                "-p", "work",
                "chat",
                "-q", "Summarize the repo",
                "--resume", "session-123",
                "-Q",
                "--unsafe-skip-confirmations",
            ]
        )
    }

    func testHermesSessionDiscoveryParsesDocumentedTableOutput() throws {
        let output = """
        Title                 Preview                     Last Active         ID
        Debug auth            Check the failing login     2026-04-07 10:23    sess_001
        UI cleanup            Polish the layout           2026-04-07 09:15    sess_002
        """

        let sessions = try HermesSessionDiscovery.parseListOutput(output)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].id, "sess_001")
        XCTAssertEqual(sessions[0].title, "Debug auth")
        XCTAssertEqual(sessions[0].preview, "Check the failing login")
        XCTAssertEqual(sessions[0].updatedAtText, "2026-04-07 10:23")
        XCTAssertNil(sessions[0].source)
    }

    func testHermesSessionDiscoveryRejectsUnparseableOutput() {
        XCTAssertThrowsError(try HermesSessionDiscovery.parseListOutput("not a session list"))
    }

    func testHermesDiagnosticsCodecProducesDiagnosticsMatch() throws {
        let record = HermesAgentDiagnosticsRecord(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessionID: "sess-hermes-1",
            modelOrProfile: "work",
            requestSummary: "Summarize repo structure",
            outputSummary: "Returned a concise summary",
            attachmentCount: 2,
            durationMs: 1500,
            status: "completed",
            referenceID: "hermes-ref-001"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let codec = HermesAgentHistoryCodec()
        let entry = codec.entry(for: record, data: data)

        XCTAssertEqual(entry.toolID, .hermesAgent)
        XCTAssertEqual(entry.referenceID, "hermes-ref-001")
        XCTAssertEqual(entry.diagnosticsInfo?.title, "Hermes Agent")
        XCTAssertEqual(entry.sessionID, "sess-hermes-1")

        let definition = try XCTUnwrap(HistoryDefinitionRegistry.shared.definition(for: .hermesAgent))
        let loaded = try definition.loadEntry(data)
        let match = try XCTUnwrap(definition.diagnosticsMatch(loaded, "hermes-ref-001"))

        XCTAssertEqual(match.title, "Hermes Agent")
        XCTAssertEqual(match.sessionID, "sess-hermes-1")
        XCTAssertTrue(match.detail.contains("attachments=2"))
    }

    func testHermesSettingsDraftDoesNotMutateStoreUntilApplied() {
        let store = HermesSettingsStore.shared
        store.hermesPath = "/usr/local/bin/hermes"
        store.model = "model-a"
        store.profile = "profile-a"
        store.extraArguments = "--flag-a"

        var draft = HermesSettingsDraft(store: store)
        draft.hermesPath = "/tmp/hermes"
        draft.model = "model-b"
        draft.profile = "profile-b"
        draft.extraArguments = "--flag-b"

        XCTAssertEqual(store.hermesPath, "/usr/local/bin/hermes")
        XCTAssertEqual(store.model, "model-a")
        XCTAssertEqual(store.profile, "profile-a")
        XCTAssertEqual(store.extraArguments, "--flag-a")

        draft.apply(to: store)

        XCTAssertEqual(store.hermesPath, "/tmp/hermes")
        XCTAssertEqual(store.model, "model-b")
        XCTAssertEqual(store.profile, "profile-b")
        XCTAssertEqual(store.extraArguments, "--flag-b")
    }

    func testHermesAgentViewStateResetClearsConversationState() {
        var state = HermesAgentViewState(
            messages: [HermesChatMessage.user("hello")],
            timelineEntries: [HermesTimelineEntry(phase: .waitingForResponse, status: .running, detail: "waiting")],
            attachments: [
                HermesAttachmentReference(
                    fileURL: URL(fileURLWithPath: "/tmp/demo.txt"),
                    displayName: "demo.txt",
                    kindDescription: "text",
                    sizeBytes: nil
                )
            ],
            draftText: "draft",
            isRunning: true,
            activeReferenceID: "ref-1",
            activeSessionID: "sess-1",
            errorBanner: "bad"
        )

        state.resetForNewChat()

        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(state.timelineEntries.isEmpty)
        XCTAssertTrue(state.attachments.isEmpty)
        XCTAssertEqual(state.draftText, "")
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.activeReferenceID, "")
        XCTAssertNil(state.activeSessionID)
        XCTAssertEqual(state.errorBanner, "")
    }

    func testHermesAgentViewStateDisablesSendWithoutInput() {
        XCTAssertTrue(
            HermesAgentViewState.sendDisabled(
                draftText: "   ",
                attachments: [],
                isRunning: false,
                isAvailable: true
            )
        )

        XCTAssertFalse(
            HermesAgentViewState.sendDisabled(
                draftText: "inspect this",
                attachments: [],
                isRunning: false,
                isAvailable: true
            )
        )

        XCTAssertFalse(
            HermesAgentViewState.sendDisabled(
                draftText: "   ",
                attachments: [
                    HermesAttachmentReference(
                        fileURL: URL(fileURLWithPath: "/tmp/demo.txt"),
                        displayName: "demo.txt",
                        kindDescription: "text",
                        sizeBytes: nil
                    )
                ],
                isRunning: false,
                isAvailable: true
            )
        )

        XCTAssertTrue(
            HermesAgentViewState.sendDisabled(
                draftText: "inspect this",
                attachments: [],
                isRunning: true,
                isAvailable: true
            )
        )
    }
}