import AppKit
import CodeToolCore
import CodeToolUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        CodeToolTextInputConfiguration.registerAppDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ObservabilitySystem.shared.bootstrap()
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.backgroundColor = .clear
                window.isOpaque = false
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.toolbarStyle = .unifiedCompact
                window.isMovableByWindowBackground = false
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ObservabilitySystem.shared.applicationWillTerminate()
    }
}
