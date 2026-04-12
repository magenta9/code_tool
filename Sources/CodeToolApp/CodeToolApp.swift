import SwiftUI
import AppKit
import CodeToolCore

private struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceCommandActions) private var workspaceCommandActions

    var body: some Commands {
        CommandMenu("Workspace") {
            Button("Show Landing") {
                workspaceCommandActions?.showLanding()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(workspaceCommandActions == nil)

            Button("Toggle Sidebar") {
                workspaceCommandActions?.toggleSidebar()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(workspaceCommandActions == nil)
        }
    }
}

@main
struct CodeToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About CodeTool") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "CodeTool",
                            NSApplication.AboutPanelOptionKey.version: version
                        ]
                    )
                }
            }

            WorkspaceCommands()
        }
    }
}
