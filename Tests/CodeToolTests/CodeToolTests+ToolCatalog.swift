import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation
@testable import CodeToolUI

extension CodeToolTests {
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

        XCTAssertNotEqual(tool1, tool2)
        XCTAssertEqual(Set([tool1, tool2]).count, 2)
    }

    func testRegistryDefaultsNotEmpty() {
        XCTAssertFalse(ToolRegistry.defaults.isEmpty)
    }

    func testEveryToolIDHasCatalogEntry() {
        let bundled = ToolRegistry.bundledToolIDs
        for toolID in ToolID.allCases {
            XCTAssertTrue(bundled.contains(toolID), "ToolID.\(toolID) has no catalog entry")
        }
    }

    func testCatalogToolIDsAreUnique() {
        let ids = ToolRegistry.defaults.compactMap(\.toolID)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate toolIDs in catalog")
    }

    func testCatalogRouteSlugsAreUnique() {
        let slugs = ToolRegistry.defaults.compactMap(\.toolID).map(\.routeSlug)
        XCTAssertEqual(slugs.count, Set(slugs).count, "Duplicate route slugs in catalog")
    }

    func testCatalogContainsAllExpectedToolIDs() {
        XCTAssertEqual(ToolRegistry.bundledToolIDs, Set(ToolID.allCases))
    }

    func testBundledCatalogEntriesMirrorToolRegistryDefaults() {
        XCTAssertEqual(
            ToolCatalog.bundled.map(\.id),
            ToolRegistry.defaults.compactMap(\.toolID)
        )
        XCTAssertEqual(
            ToolCatalog.bundled.map(\.title),
            ToolRegistry.defaults.map(\.name)
        )
    }

    func testDestinationRegistryCoversBundledCatalog() {
        XCTAssertEqual(
            ToolDestinationRegistry.registeredToolIDs,
            Set(ToolCatalog.bundled.map(\.id))
        )
    }

    func testAIChatCatalogEntryUsesMiniMaxCopy() {
        let entry = ToolCatalog.entry(for: .aiChat)

        XCTAssertEqual(entry?.title, "AI Chat")
        XCTAssertEqual(entry?.category, .aiTools)
        XCTAssertTrue(entry?.description.contains("MiniMax") == true)
        XCTAssertFalse(entry?.description.contains("Claude") == true)
    }

    func testProviderSettingsTabsExcludeClaude() {
        XCTAssertEqual(ToolSettingsTab.allCases, [.minimax, .diagnostics])
        XCTAssertEqual(ToolSettingsTab.allCases.map(\.title), ["MiniMax", "Diagnostics"])
    }

    func testRegistryCanRegisterAdditionalTool() {
        let originalCount = ToolRegistry.defaults.count
        ToolRegistry.defaults.append(Tool(name: "Extra Tool", description: "Extra.", systemImage: "star"))
        XCTAssertEqual(ToolRegistry.defaults.count, originalCount + 1)
    }

    func testMiniMaxSettingsDraftDoesNotMutateStoreUntilApplied() {
        let store = MiniMaxSettingsStore.shared
        store.apiKey = "original-api-key"
        store.baseURL = "https://example.com/v1"
        store.chatModel = "chat-original"
        store.speechModel = "speech-original"
        store.imageModel = "image-original"
        store.musicModel = "music-original"

        var draft = MiniMaxSettingsDraft(store: store)
        draft.apiKey = "draft-api-key"
        draft.baseURL = "https://draft.example.com/v1"
        draft.chatModel = "chat-draft"
        draft.speechModel = "speech-draft"
        draft.imageModel = "image-draft"
        draft.musicModel = "music-draft"

        XCTAssertEqual(store.apiKey, "original-api-key")
        XCTAssertEqual(store.baseURL, "https://example.com/v1")
        XCTAssertEqual(store.chatModel, "chat-original")
        XCTAssertEqual(store.speechModel, "speech-original")
        XCTAssertEqual(store.imageModel, "image-original")
        XCTAssertEqual(store.musicModel, "music-original")

        draft.apply(to: store)

        XCTAssertEqual(store.apiKey, "draft-api-key")
        XCTAssertEqual(store.baseURL, "https://draft.example.com/v1")
        XCTAssertEqual(store.chatModel, "chat-draft")
        XCTAssertEqual(store.speechModel, "speech-draft")
        XCTAssertEqual(store.imageModel, "image-draft")
        XCTAssertEqual(store.musicModel, "music-draft")
    }

    func testToolViewCacheRetainsVisitedToolsInSelectionOrder() {
        var retainedToolIDs: [ToolID] = []

        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .jsonTool)
        XCTAssertEqual(retainedToolIDs, [.jsonTool])

        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .imageConverter)
        XCTAssertEqual(retainedToolIDs, [.jsonTool, .imageConverter])

        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .jsonTool)
        XCTAssertEqual(retainedToolIDs, [.imageConverter, .jsonTool])

        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: nil)
        XCTAssertEqual(retainedToolIDs, [.imageConverter, .jsonTool])
    }

    func testToolViewCacheCapsRetainedTools() {
        var retainedToolIDs: [ToolID] = []

        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .jsonTool)
        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .imageConverter)
        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .jsonDiff)
        retainedToolIDs = ToolViewCache.retainedToolIDs(current: retainedToolIDs, selectedToolID: .timestampConverter)

        XCTAssertEqual(retainedToolIDs.count, ToolViewCache.maximumRetainedToolCount)
        XCTAssertEqual(retainedToolIDs, [.imageConverter, .jsonDiff, .timestampConverter])
    }

    func testToolStatusItemIDsRespectStableAndGeneratedModes() {
        let explicit = ToolStatusItem(id: "current-time", title: "123 s", systemImage: "clock")
        let generatedA = ToolStatusItem(title: "A", systemImage: "clock")
        let generatedB = ToolStatusItem(title: "B", systemImage: "globe")

        XCTAssertEqual(explicit.id, "current-time")
        XCTAssertNotEqual(generatedA.id, generatedB.id)
    }

    func testToolVisibilityStateReflectsSelection() {
        let selected = ToolVisibilityState(selectedToolID: .timestampConverter)
        XCTAssertTrue(selected.isVisible(toolID: .timestampConverter))
        XCTAssertFalse(selected.isVisible(toolID: .jsonTool))
        XCTAssertFalse(selected.isVisible(toolID: nil))

        let empty = ToolVisibilityState(selectedToolID: nil)
        XCTAssertFalse(empty.isVisible(toolID: .timestampConverter))
    }

    func testToolUIActivityTracksVisibility() {
        let hidden = ToolUIActivity(isVisible: false)
        XCTAssertFalse(hidden.allowsInteractiveEffects)
        XCTAssertFalse(hidden.allowsDecorativeAnimations)

        let visible = ToolUIActivity(isVisible: true)
        XCTAssertTrue(visible.allowsInteractiveEffects)
        XCTAssertTrue(visible.allowsDecorativeAnimations)
    }
}
