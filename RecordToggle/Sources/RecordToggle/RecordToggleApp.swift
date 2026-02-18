import AppKit
import SwiftUI
import KeyboardShortcuts

@main
struct RecordToggleApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)  // Show in dock

        ProcessInfo.processInfo.disableAutomaticTermination("Record Toggle")

        let delegate = AppDelegate()
        app.delegate = delegate

        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow!
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = MainView(
            appState: appState,
            openSettings: openSettings,
            openHistory: openHistory
        )

        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "Record Toggle"
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.isMovableByWindowBackground = true
        mainWindow.contentViewController = NSHostingController(rootView: contentView)
        mainWindow.center()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func openSettings() {
        let controller = NSHostingController(rootView: SettingsView(config: appState.config))
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 420, height: 300))
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistory() {
        let controller = NSHostingController(rootView: HistoryView(history: appState.history))
        let window = NSWindow(contentViewController: controller)
        window.title = "History"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
