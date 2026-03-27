import XCTest
@testable import CodeToolCore

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
        // Different UUIDs means they are not equal
        XCTAssertNotEqual(tool1, tool2)
        let set: Set<Tool> = [tool1, tool2]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - ToolRegistry tests

    func testRegistryDefaultsNotEmpty() {
        XCTAssertFalse(ToolRegistry.defaults.isEmpty)
    }

    func testRegistryDefaultNamesAreUnique() {
        let names = ToolRegistry.defaults.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count)
    }
}
