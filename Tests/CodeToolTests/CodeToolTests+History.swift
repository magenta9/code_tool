import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

extension CodeToolTests {
    func testUnifiedRepositoryAppendAndListEntries() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedHistory")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let record = ChatHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            systemPrompt: "You are helpful",
            messages: [ChatMessageRecord(role: "user", content: "Hello unified")],
            model: "test-model",
            promptTokens: 10,
            completionTokens: 20,
            totalTokens: 30,
            referenceID: "unified-ref-001"
        )

        let codec = ChatHistoryCodec()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(record)
        let entry = codec.entry(for: record, data: data)
        try await HistoryStore.shared.upsert(entry, assets: [])

        let entries = try await HistoryStore.shared.list(HistoryQuery(toolID: .chat))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, record.id)
        XCTAssertEqual(entries.first?.toolID, .chat)
        XCTAssertEqual(entries.first?.summary.title, "Hello unified")
        XCTAssertEqual(entries.first?.referenceID, "unified-ref-001")

        let legacyRecords: [ChatHistoryRecord] = try await HistoryStore.shared.listChat()
        XCTAssertEqual(legacyRecords.count, 1)
        XCTAssertEqual(legacyRecords.first?.id, record.id)
    }

    func testCodecBackedUpsertAndListChatPayloads() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "CodecHistoryChat")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let record = ChatHistoryRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            systemPrompt: "Stay concise",
            messages: [
                ChatMessageRecord(role: "user", content: "Hello"),
                ChatMessageRecord(role: "assistant", content: "Hi"),
            ],
            model: "chat-model",
            promptTokens: 10,
            completionTokens: 4,
            totalTokens: 14,
            referenceID: "chat-ref-1"
        )

        try await HistoryStore.shared.upsert(record, using: ChatHistoryCodec())

        let records = try await HistoryStore.shared.payloads(using: ChatHistoryCodec())
        XCTAssertEqual(records.map(\.id), [record.id])
        XCTAssertEqual(records.first?.referenceID, "chat-ref-1")
    }

    func testCodecBackedUpsertAndListJSONPayloads() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "CodecHistoryJSON")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let record = JSONToolHistoryRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 300),
            operation: "format",
            inputText: "{\"hello\":true}",
            outputText: "{\n  \"hello\" : true\n}",
            stats: "Keys: 1"
        )

        try await HistoryStore.shared.upsert(record, using: JSONToolHistoryCodec())

        let records = try await HistoryStore.shared.payloads(using: JSONToolHistoryCodec())
        XCTAssertEqual(records.map(\.id), [record.id])
        XCTAssertEqual(records.first?.operation, "format")
    }

    func testUnifiedRepositoryDeleteEntry() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedDelete")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let recordID = UUID()
        let record = JSONToolHistoryRecord(
            id: recordID,
            createdAt: Date(),
            operation: "format",
            inputText: "{\"a\":1}",
            outputText: "{\n  \"a\": 1\n}",
            stats: "1 key"
        )

        try await HistoryStore.shared.save(record)
        let savedEntries = try await HistoryStore.shared.list(HistoryQuery(toolID: .jsonTool))
        XCTAssertEqual(savedEntries.count, 1)

        try await HistoryStore.shared.delete(toolID: .jsonTool, id: recordID)
        let deletedEntries = try await HistoryStore.shared.list(HistoryQuery(toolID: .jsonTool))
        XCTAssertEqual(deletedEntries.count, 0)
    }

    func testUnifiedRepositoryCrossToolQuery() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedCrossTool")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let refID = "cross-tool-ref-001"

        try await HistoryStore.shared.save(
            ChatHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                systemPrompt: "",
                messages: [ChatMessageRecord(role: "user", content: "Hello")],
                model: "m1",
                promptTokens: 1,
                completionTokens: 1,
                totalTokens: 2,
                referenceID: refID
            )
        )
        try await HistoryStore.shared.save(
            SpeechHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                inputText: "Hello speech",
                voice: "Voice-1",
                speed: 1.0,
                volume: 1.0,
                pitch: 0,
                outputFormat: "mp3",
                model: "speech-model",
                durationMs: 1200,
                audioFileName: "speech.mp3",
                referenceID: refID
            ),
            audioData: Data("speech".utf8)
        )

        let entries = try await HistoryStore.shared.list(HistoryQuery(referenceID: refID))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.toolID)), Set([.chat, .speech]))
    }

    func testUnifiedRepositoryDiagnosticsMatchesUsesCodecs() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedDiag")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let refID = "diag-unified-001"
        try await HistoryStore.shared.save(
            ChatHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                systemPrompt: "",
                messages: [ChatMessageRecord(role: "user", content: "test")],
                model: "MiniMax-M2.7",
                promptTokens: 1,
                completionTokens: 1,
                totalTokens: 2,
                referenceID: refID
            )
        )

        let matches = try await HistoryStore.shared.diagnosticsMatches(referenceID: refID)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "AI Chat")
        XCTAssertNil(matches.first?.sessionID)
        XCTAssertEqual(matches.first?.category, "chat")
    }

    func testHistoryDefinitionRegistryCoversAllToolIDs() {
        let registry = HistoryDefinitionRegistry.shared
        for toolID in HistoryToolID.allCases {
            XCTAssertNotNil(registry.definition(for: toolID), "Missing definition for \(toolID.rawValue)")
        }
    }

    func testUnifiedListWithLimit() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedLimit")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        for i in 0..<3 {
            try await HistoryStore.shared.save(
                JSONToolHistoryRecord(
                    id: UUID(),
                    createdAt: Date().addingTimeInterval(Double(i)),
                    operation: "format",
                    inputText: "input \(i)",
                    outputText: "output \(i)",
                    stats: "\(i) keys"
                )
            )
        }

        let limited = try await HistoryStore.shared.list(HistoryQuery(toolID: .jsonTool, limit: 2))
        let allEntries = try await HistoryStore.shared.list(HistoryQuery(toolID: .jsonTool))
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(allEntries.count, 3)
    }

    func testUnifiedClearByTool() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedClear")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        try await HistoryStore.shared.save(
            JSONToolHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                operation: "format",
                inputText: "x",
                outputText: "y",
                stats: "1"
            )
        )

        let countBeforeClear = try await HistoryStore.shared.count(toolID: .jsonTool)
        XCTAssertEqual(countBeforeClear, 1)
        try await HistoryStore.shared.clear(toolID: .jsonTool)
        let countAfterClear = try await HistoryStore.shared.count(toolID: .jsonTool)
        XCTAssertEqual(countAfterClear, 0)
    }

    func testCodecDiagnosticsInfoIsNilForDevTools() {
        let codec = JSONToolHistoryCodec()
        let record = JSONToolHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            operation: "format",
            inputText: "x",
            outputText: "y",
            stats: "1"
        )

        XCTAssertNil(codec.diagnosticsInfo(for: record))
        XCTAssertNil(codec.referenceID(for: record))
    }

    func testImageCodecAssetFileNames() {
        let record = ImageHistoryRecord(
            prompt: "cat",
            imageCount: 1,
            model: "test",
            referenceImages: [
                ImageReferenceRecord(fileName: "ref-1.png", mimeType: "image/png", sizeBytes: 100)
            ],
            outputImageFileNames: ["out-1.png"],
            referenceID: "ref-img"
        )

        XCTAssertEqual(ImageHistoryCodec().assetFileNames(for: record), ["ref-1.png", "out-1.png"])
    }

    func testUnifiedSaveOverwritesByID() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedOverwrite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let stableID = UUID()
        let stableCreatedAt = Date()
        let codec = ChatHistoryCodec()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let record1 = ChatHistoryRecord(
            id: stableID,
            createdAt: stableCreatedAt,
            systemPrompt: "",
            messages: [ChatMessageRecord(role: "user", content: "Hello")],
            model: "MiniMax-M2.7",
            promptTokens: 1,
            completionTokens: 1,
            totalTokens: 2,
            referenceID: "ref-overwrite"
        )
        try await HistoryStore.shared.upsert(codec.entry(for: record1, data: encoder.encode(record1)), assets: [])

        var entries = try await HistoryStore.shared.list(HistoryQuery(toolID: .chat))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, stableID)

        let record2 = ChatHistoryRecord(
            id: stableID,
            createdAt: stableCreatedAt,
            systemPrompt: "",
            messages: [
                ChatMessageRecord(role: "user", content: "Hello"),
                ChatMessageRecord(role: "assistant", content: "Hi there"),
            ],
            model: "MiniMax-M2.7",
            promptTokens: 2,
            completionTokens: 2,
            totalTokens: 4,
            referenceID: "ref-overwrite-2"
        )
        try await HistoryStore.shared.upsert(codec.entry(for: record2, data: encoder.encode(record2)), assets: [])

        entries = try await HistoryStore.shared.list(HistoryQuery(toolID: .chat))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, stableID)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatHistoryRecord.self, from: try XCTUnwrap(entries.first?.payloadData))
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.totalTokens, 4)
    }

    func testClearAllRemovesMiniMaxAndDevToolHistory() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedClearAll")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        try await HistoryStore.shared.save(
            ChatHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                systemPrompt: "",
                messages: [ChatMessageRecord(role: "user", content: "hi")],
                model: "MiniMax-M2.7",
                promptTokens: 1,
                completionTokens: 1,
                totalTokens: 2,
                referenceID: "ref-clearall-chat"
            )
        )
        try await HistoryStore.shared.save(
            JSONToolHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                operation: "format",
                inputText: "x",
                outputText: "y",
                stats: "1"
            )
        )

        try await HistoryStore.shared.clearAll()

        let chatEntries = try await HistoryStore.shared.list(HistoryQuery(toolID: .chat))
        let jsonEntries = try await HistoryStore.shared.list(HistoryQuery(toolID: .jsonTool))
        XCTAssertEqual(chatEntries.count, 0)
        XCTAssertEqual(jsonEntries.count, 0)
    }

    func testUnifiedDeleteIsIdempotent() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedIdempotent")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        try await HistoryStore.shared.delete(toolID: .chat, id: UUID())
    }

    func testUnifiedDeleteImageWithAssets() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedImgDel")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let recordID = UUID()
        let refFileName = "ref-\(recordID.uuidString).png"
        let outFileName = "out-\(recordID.uuidString).png"

        let record = ImageHistoryRecord(
            id: recordID,
            prompt: "a cat",
            imageCount: 1,
            model: "test-model",
            referenceImages: [ImageReferenceRecord(fileName: refFileName, mimeType: "image/png", sizeBytes: 100)],
            outputImageFileNames: [outFileName],
            referenceID: "ref-img-del"
        )

        try await HistoryStore.shared.save(
            record,
            outputImages: [Data("output-img".utf8)],
            referenceImageData: [Data("ref-img".utf8)]
        )

        let referenceImageData = try await HistoryStore.shared.loadData(category: .image, fileName: refFileName)
        XCTAssertFalse(referenceImageData.isEmpty)

        try await HistoryStore.shared.delete(toolID: .image, id: recordID)

        let remainingImageEntries = try await HistoryStore.shared.list(HistoryQuery(toolID: .image))
        XCTAssertEqual(remainingImageEntries.count, 0)
        do {
            _ = try await HistoryStore.shared.loadData(category: .image, fileName: refFileName)
            XCTFail("Expected ref image file to be deleted")
        } catch {
        }
        do {
            _ = try await HistoryStore.shared.loadData(category: .image, fileName: outFileName)
            XCTFail("Expected output image file to be deleted")
        } catch {
        }
    }

    func testDiagnosticsMatchesOnlyReturnsAITools() async throws {
        let tempDir = try makeTemporaryDirectory(prefix: "UnifiedDiagAI")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        let refID = "diag-ai-only-001"
        try await HistoryStore.shared.save(
            ChatHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                systemPrompt: "",
                messages: [ChatMessageRecord(role: "user", content: "Hello")],
                model: "m1",
                promptTokens: 1,
                completionTokens: 1,
                totalTokens: 2,
                referenceID: refID
            )
        )

        let matches = try await HistoryStore.shared.diagnosticsMatches(referenceID: refID)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "AI Chat")
    }

    func testAllCodecSummariesMatchLegacyDrawerConformances() throws {
        let jsonRecord = JSONToolHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            operation: "format",
            inputText: "{\"key\":\"value\"}",
            outputText: "formatted",
            stats: "1 key"
        )
        let jsonSummary = JSONToolHistoryCodec().summary(for: jsonRecord)
        XCTAssertEqual(jsonSummary.title, jsonRecord.drawerTitle)
        XCTAssertEqual(jsonSummary.subtitle, jsonRecord.drawerSubtitle)
        XCTAssertEqual(jsonSummary.icon, jsonRecord.drawerIcon)

        let diffRecord = JSONDiffHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            leftText: "{}",
            rightText: "{\"a\":1}",
            totalDiffs: 1,
            addedCount: 1,
            removedCount: 0,
            modifiedCount: 0
        )
        let diffSummary = JSONDiffHistoryCodec().summary(for: diffRecord)
        XCTAssertEqual(diffSummary.title, diffRecord.drawerTitle)
        XCTAssertEqual(diffSummary.subtitle, diffRecord.drawerSubtitle)
        XCTAssertEqual(diffSummary.icon, diffRecord.drawerIcon)

        let tsRecord = TimestampHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            inputValue: "1700000000",
            direction: "timestampToDate",
            selectedDateISO8601: nil,
            resultISO8601: "2023-11-14T22:13:20Z",
            resultLocal: "Nov 14, 2023",
            resultTimestamp: "1700000000"
        )
        let tsSummary = TimestampHistoryCodec().summary(for: tsRecord)
        XCTAssertEqual(tsSummary.title, tsRecord.drawerTitle)
        XCTAssertEqual(tsSummary.subtitle, tsRecord.drawerSubtitle)
        XCTAssertEqual(tsSummary.icon, tsRecord.drawerIcon)

        let jwtRecord = JWTHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            mode: "decode",
            jwtInput: "eyJ...",
            headerJSON: "{}",
            payloadJSON: "{\"sub\":\"1234\"}",
            expirationInfo: "expired"
        )
        let jwtSummary = JWTHistoryCodec().summary(for: jwtRecord)
        XCTAssertEqual(jwtSummary.title, jwtRecord.drawerTitle)
        XCTAssertEqual(jwtSummary.subtitle, jwtRecord.drawerSubtitle)
        XCTAssertEqual(jwtSummary.icon, jwtRecord.drawerIcon)

        let wcRecord = WordCloudHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            inputText: "hello world hello",
            inputPreview: "hello world hello",
            topWords: "hello,world",
            minWordLength: 3,
            maxWords: 50,
            ignoreStopWords: true
        )
        let wcSummary = WordCloudHistoryCodec().summary(for: wcRecord)
        XCTAssertEqual(wcSummary.title, wcRecord.drawerTitle)
        XCTAssertEqual(wcSummary.subtitle, wcRecord.drawerSubtitle)
        XCTAssertEqual(wcSummary.icon, wcRecord.drawerIcon)

        let icRecord = ImageConverterHistoryRecord(
            id: UUID(),
            createdAt: Date(),
            mode: "imageToBase64",
            base64Text: "abc",
            base64Preview: "abc",
            imageInfo: "photo.png",
            imageFileName: nil
        )
        let icSummary = ImageConverterHistoryCodec().summary(for: icRecord)
        XCTAssertEqual(icSummary.title, icRecord.drawerTitle)
        XCTAssertEqual(icSummary.subtitle, icRecord.drawerSubtitle)
        XCTAssertEqual(icSummary.icon, icRecord.drawerIcon)
    }
}
