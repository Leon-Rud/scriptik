import AppKit
import SwiftUI
import KeyboardShortcuts

@main
struct ScriptikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var circlePanel: FloatingPanel?
    private var toastPanel: FloatingPanel?
    private var toastDismissTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show the persistent floating circle button
        showFloatingCircle()

        // Wire up transcription toast
        appState.onTranscriptionComplete = { [weak self] text in
            self?.showToast(text: text)
        }
    }

    private func showFloatingCircle() {
        let size: CGFloat = 40
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size))

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - size - 16
            let y = screenFrame.minY + 16
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.show {
            FloatingCircleView(appState: self.appState)
        }

        circlePanel = panel
    }

    private func showToast(text: String) {
        toastDismissTask?.cancel()
        toastPanel?.orderOut(nil)
        toastPanel = nil

        let toastWidth: CGFloat = 320
        let toastHeight: CGFloat = 130
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight))

        // Position above the circle panel; clamp to screen edges
        if let screen = NSScreen.main {
            let circleFrame = circlePanel?.frame ?? NSRect(
                x: screen.visibleFrame.midX - 40,
                y: screen.visibleFrame.minY + 16,
                width: 80, height: 80
            )
            let x = max(screen.visibleFrame.minX + 8,
                        min(circleFrame.midX - toastWidth / 2,
                            screen.visibleFrame.maxX - toastWidth - 8))
            let y = circleFrame.maxY + 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.show {
            ResultToastView(text: text)
        }

        toastPanel = panel

        // Auto-dismiss after 6 seconds
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.toastPanel?.orderOut(nil)
            self?.toastPanel = nil
        }
    }
}
