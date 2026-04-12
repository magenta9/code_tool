import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

extension CodeToolTests {
    func testWorkspaceToolSelectionCommandsMirrorBundledCatalogOrder() {
        let commands = WorkspaceCommandCatalog.toolSelectionCommands
        let expectedKeys: [Character] = [
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "0",
        ]
        let expectedModifiers: [WorkspaceCommandModifiers] = [
            .command,
            .command,
            .command,
            .command,
            .command,
            .command,
            .command,
            .command,
            .command,
            .commandShift,
        ]

        XCTAssertEqual(commands.map(\.toolID), ToolCatalog.bundled.map(\.id))
        XCTAssertEqual(commands.map(\.title), ToolCatalog.bundled.map(\.title))
        XCTAssertEqual(commands.map(\.category), ToolCatalog.bundled.map(\.category))
        XCTAssertEqual(commands.map { $0.shortcut.key }, expectedKeys)
        XCTAssertEqual(commands.map { $0.shortcut.modifiers }, expectedModifiers)
    }

    func testWorkspaceCommandCatalogDefinesGlobalShortcuts() {
        XCTAssertEqual(WorkspaceCommandCatalog.showLanding.title, "Show Landing")
        XCTAssertEqual(WorkspaceCommandCatalog.showLanding.shortcut.key, "0")
        XCTAssertEqual(WorkspaceCommandCatalog.showLanding.shortcut.modifiers, .command)

        XCTAssertEqual(WorkspaceCommandCatalog.toggleSidebar.title, "Toggle Sidebar")
        XCTAssertEqual(WorkspaceCommandCatalog.toggleSidebar.shortcut.key, "\\")
        XCTAssertEqual(WorkspaceCommandCatalog.toggleSidebar.shortcut.modifiers, .command)

        XCTAssertEqual(WorkspaceCommandCatalog.focusSearch.title, "Focus Search")
        XCTAssertEqual(WorkspaceCommandCatalog.focusSearch.shortcut.key, "k")
        XCTAssertEqual(WorkspaceCommandCatalog.focusSearch.shortcut.modifiers, .command)

        XCTAssertEqual(WorkspaceCommandCatalog.openSettings.title, "Settings...")
        XCTAssertEqual(WorkspaceCommandCatalog.openSettings.shortcut.key, ",")
        XCTAssertEqual(WorkspaceCommandCatalog.openSettings.shortcut.modifiers, .command)
    }

    func testFocusSearchCommandPlanRevealsSidebarOnlyWhenNeeded() {
        XCTAssertEqual(
            WorkspaceSearchCommandPlan.forCurrentSidebarVisibility(true),
            WorkspaceSearchCommandPlan(revealsSidebar: false, focusesSearchField: true)
        )
        XCTAssertEqual(
            WorkspaceSearchCommandPlan.forCurrentSidebarVisibility(false),
            WorkspaceSearchCommandPlan(revealsSidebar: true, focusesSearchField: true)
        )
    }

    func testSearchFocusStateRequestsImmediateFocusWhenSidebarIsVisible() {
        var state = WorkspaceSearchFocusState(
            isSidebarVisible: true,
            isSearchFieldFocused: false,
            hasPendingFocusRequest: false
        )

        state.requestFocus()

        XCTAssertTrue(state.isSidebarVisible)
        XCTAssertTrue(state.isSearchFieldFocused)
        XCTAssertFalse(state.hasPendingFocusRequest)
    }

    func testSearchFocusStateDefersFocusUntilSidebarBecomesVisible() {
        var state = WorkspaceSearchFocusState(
            isSidebarVisible: false,
            isSearchFieldFocused: false,
            hasPendingFocusRequest: false
        )

        state.requestFocus()

        XCTAssertTrue(state.isSidebarVisible)
        XCTAssertFalse(state.isSearchFieldFocused)
        XCTAssertTrue(state.hasPendingFocusRequest)

        state.handleSidebarVisibilityChange(true)

        XCTAssertTrue(state.isSearchFieldFocused)
        XCTAssertFalse(state.hasPendingFocusRequest)
    }
}
