import AppKit
import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State private var settingsOpen = false
    @State private var historyOpen = false

    var body: some View {
        // Status
        Text(appState.statusText)
            .foregroundStyle(.secondary)

        Divider()

        // Toggle recording
        if appState.recorder.isRecording {
            Button("Stop Recording") { appState.toggle() }
        } else if appState.transcriber.isTranscribing {
            Text("Transcribing…")
                .foregroundStyle(.secondary)
        } else {
            Button("Start Recording") { appState.toggle() }
        }

        Divider()

        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")

        Button("History…") { openHistory() }
            .keyboardShortcut("h")

        Divider()

        Button("Quit Scriptik") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openSettings() {
        openWindow(
            view: SettingsView(config: appState.config),
            title: "Settings",
            size: NSSize(width: 420, height: 300),
            resizable: false
        )
    }

    private func openHistory() {
        openWindow(
            view: HistoryView(history: appState.history),
            title: "History",
            size: NSSize(width: 700, height: 500),
            resizable: true
        )
    }

    private func openWindow<V: View>(view: V, title: String, size: NSSize, resizable: Bool) {
        // Reuse existing window if open
        for window in NSApp.windows where window.title == title {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable { style.insert(.resizable) }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.setContentSize(size)
        window.styleMask = style
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
