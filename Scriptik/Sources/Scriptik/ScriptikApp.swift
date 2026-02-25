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
    private var positionSaveTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show the persistent floating circle button
        showFloatingCircle()

        // Wire up transcription toast
        appState.onTranscriptionComplete = { [weak self] text in
            self?.showToast(text: text)
        }
    }

    // MARK: - Right-Click Menu

    @objc private func handleRightClick(_ recognizer: NSClickGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let menu = NSMenu()

        if appState.recorder.isRecording {
            menu.addItem(withTitle: "Cancel Recording", action: #selector(menuCancelRecording), keyEquivalent: "")
                .target = self
            menu.addItem(.separator())
        }

        menu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "History", action: #selector(menuOpenHistory), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Scriptik", action: #selector(menuQuit), keyEquivalent: "")
            .target = self

        let location = recognizer.location(in: view)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    @objc private func menuCancelRecording() { appState.cancelRecording() }
    @objc private func menuOpenSettings() { appState.showSettings = true }
    @objc private func menuOpenHistory() { appState.showHistory = true }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func showFloatingCircle() {
        let size: CGFloat = 46
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size))

        let config = appState.config
        if config.circlePositionX >= 0 && config.circlePositionY >= 0 {
            panel.setFrameOrigin(NSPoint(x: config.circlePositionX, y: config.circlePositionY))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - size - 16
            let y = screenFrame.minY + 16
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.show {
            FloatingCircleView(appState: self.appState)
        }

        // Right-click context menu
        if let contentView = panel.contentView {
            let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
            rightClick.buttonMask = 0x2
            contentView.addGestureRecognizer(rightClick)
        }

        circlePanel = panel

        // Observe panel moves to persist position (debounced)
        NotificationCenter.default.addObserver(
            self, selector: #selector(circlePanelDidMove(_:)),
            name: NSWindow.didMoveNotification, object: panel
        )
    }

    @objc private func circlePanelDidMove(_ notification: Notification) {
        positionSaveTask?.cancel()
        positionSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, let frame = self.circlePanel?.frame else { return }
            self.appState.config.circlePositionX = Double(frame.origin.x)
            self.appState.config.circlePositionY = Double(frame.origin.y)
            self.appState.config.save()
        }
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
