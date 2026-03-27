import XCTest
@testable import CodeToolCore

#if canImport(SwiftUI)
import SwiftUI
#endif

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

    override func setUp() {
        super.setUp()
        savedDefaults = ToolRegistry.defaults
    }

    override func tearDown() {
        ToolRegistry.defaults = savedDefaults
        super.tearDown()
    }

    func testRegistryDefaultsNotEmpty() {
        XCTAssertFalse(ToolRegistry.defaults.isEmpty)
    }

    func testRegistryContainsSixTools() {
        XCTAssertEqual(ToolRegistry.defaults.count, 6)
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
            "Timestamp Converter", "JWT Tool", "Word Cloud"
        ]
        XCTAssertEqual(names, expected)
    }

    func testRegistryCanRegisterAdditionalTool() {
        let originalCount = ToolRegistry.defaults.count
        let extra = Tool(name: "Extra Tool", description: "Extra.", systemImage: "star")
        ToolRegistry.defaults.append(extra)
        XCTAssertEqual(ToolRegistry.defaults.count, originalCount + 1)
    }

    #if canImport(SwiftUI)
    func testContentViewDoesNotUseNavigationSplitView() {
        let bodyTypeDescription = String(describing: type(of: ContentView().body))
        XCTAssertFalse(bodyTypeDescription.contains("NavigationSplitView"))
    }
    #endif
}
