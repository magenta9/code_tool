import CodeToolFoundation
import SwiftUI

public enum WorkspaceCommandModifiers: Equatable {
    case command
    case commandShift

    public var eventModifiers: EventModifiers {
        switch self {
        case .command:
            return .command
        case .commandShift:
            return [.command, .shift]
        }
    }
}

public struct WorkspaceCommandShortcut: Equatable {
    public let key: Character
    public let modifiers: WorkspaceCommandModifiers

    public init(key: Character, modifiers: WorkspaceCommandModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func command(_ key: Character) -> Self {
        Self(key: key, modifiers: .command)
    }

    public static func commandShift(_ key: Character) -> Self {
        Self(key: key, modifiers: .commandShift)
    }

    public var keyEquivalent: KeyEquivalent {
        KeyEquivalent(key)
    }
}

public struct WorkspaceCommandDescriptor: Equatable {
    public let title: String
    public let shortcut: WorkspaceCommandShortcut

    public init(title: String, shortcut: WorkspaceCommandShortcut) {
        self.title = title
        self.shortcut = shortcut
    }
}

public struct WorkspaceToolCommandDescriptor: Equatable, Identifiable {
    public let toolID: ToolID
    public let title: String
    public let category: ToolCategory
    public let shortcut: WorkspaceCommandShortcut

    public var id: ToolID { toolID }

    public init(
        toolID: ToolID,
        title: String,
        category: ToolCategory,
        shortcut: WorkspaceCommandShortcut
    ) {
        self.toolID = toolID
        self.title = title
        self.category = category
        self.shortcut = shortcut
    }
}

public struct WorkspaceToolCommandGroup: Equatable, Identifiable {
    public let category: ToolCategory
    public let commands: [WorkspaceToolCommandDescriptor]

    public var id: ToolCategory { category }

    public init(category: ToolCategory, commands: [WorkspaceToolCommandDescriptor]) {
        self.category = category
        self.commands = commands
    }
}

public enum WorkspaceCommandCatalog {
    public static let showLanding = WorkspaceCommandDescriptor(
        title: "Show Landing",
        shortcut: .command("0")
    )

    public static let toggleSidebar = WorkspaceCommandDescriptor(
        title: "Toggle Sidebar",
        shortcut: .command("\\")
    )

    public static let focusSearch = WorkspaceCommandDescriptor(
        title: "Focus Search",
        shortcut: .command("k")
    )

    public static let openSettings = WorkspaceCommandDescriptor(
        title: "Settings...",
        shortcut: .command(",")
    )

    public static var toolSelectionCommands: [WorkspaceToolCommandDescriptor] {
        precondition(
            ToolCatalog.bundled.count <= 10,
            "Keyboard shortcut mapping must be redesigned when bundled tools exceed 10."
        )

        return ToolCatalog.bundled.enumerated().map { index, entry in
            WorkspaceToolCommandDescriptor(
                toolID: entry.id,
                title: entry.title,
                category: entry.category,
                shortcut: shortcutForBundledTool(at: index)
            )
        }
    }

    public static var toolSelectionCommandGroups: [WorkspaceToolCommandGroup] {
        ToolCategory.allCases.compactMap { category in
            let commands = toolSelectionCommands.filter { $0.category == category }
            return commands.isEmpty ? nil : WorkspaceToolCommandGroup(category: category, commands: commands)
        }
    }

    private static func shortcutForBundledTool(at index: Int) -> WorkspaceCommandShortcut {
        switch index {
        case 0...8:
            return .command(Character(String(index + 1)))
        case 9:
            return .commandShift("0")
        default:
            preconditionFailure("Unsupported bundled tool shortcut index: \(index)")
        }
    }
}

public struct WorkspaceSearchCommandPlan: Equatable {
    public let revealsSidebar: Bool
    public let focusesSearchField: Bool

    public init(revealsSidebar: Bool, focusesSearchField: Bool) {
        self.revealsSidebar = revealsSidebar
        self.focusesSearchField = focusesSearchField
    }

    public static func forCurrentSidebarVisibility(_ isSidebarVisible: Bool) -> Self {
        Self(revealsSidebar: !isSidebarVisible, focusesSearchField: true)
    }
}

public struct WorkspaceSearchFocusState: Equatable {
    public var isSidebarVisible: Bool
    public var isSearchFieldFocused: Bool
    public var hasPendingFocusRequest: Bool

    public init(
        isSidebarVisible: Bool,
        isSearchFieldFocused: Bool,
        hasPendingFocusRequest: Bool
    ) {
        self.isSidebarVisible = isSidebarVisible
        self.isSearchFieldFocused = isSearchFieldFocused
        self.hasPendingFocusRequest = hasPendingFocusRequest
    }

    public mutating func requestFocus() {
        let plan = WorkspaceSearchCommandPlan.forCurrentSidebarVisibility(isSidebarVisible)
        isSidebarVisible = true

        if plan.revealsSidebar {
            isSearchFieldFocused = false
            hasPendingFocusRequest = plan.focusesSearchField
        } else {
            isSearchFieldFocused = plan.focusesSearchField
            hasPendingFocusRequest = false
        }
    }

    public mutating func handleSidebarVisibilityChange(_ isVisible: Bool) {
        isSidebarVisible = isVisible

        guard isVisible else {
            clearFocus()
            return
        }

        guard hasPendingFocusRequest else {
            return
        }

        isSearchFieldFocused = true
        hasPendingFocusRequest = false
    }

    public mutating func clearFocus() {
        isSearchFieldFocused = false
        hasPendingFocusRequest = false
    }
}

public struct WorkspaceCommandActions {
    public let showLanding: () -> Void
    public let toggleSidebar: () -> Void
    public let selectTool: (ToolID) -> Void
    public let focusSearch: () -> Void
    public let showSettings: () -> Void

    public init(
        showLanding: @escaping () -> Void = {},
        toggleSidebar: @escaping () -> Void = {},
        selectTool: @escaping (ToolID) -> Void = { _ in },
        focusSearch: @escaping () -> Void = {},
        showSettings: @escaping () -> Void = {}
    ) {
        self.showLanding = showLanding
        self.toggleSidebar = toggleSidebar
        self.selectTool = selectTool
        self.focusSearch = focusSearch
        self.showSettings = showSettings
    }
}

private struct WorkspaceCommandActionsFocusedValueKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

public extension FocusedValues {
    var workspaceCommandActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandActionsFocusedValueKey.self] }
        set { self[WorkspaceCommandActionsFocusedValueKey.self] = newValue }
    }
}
