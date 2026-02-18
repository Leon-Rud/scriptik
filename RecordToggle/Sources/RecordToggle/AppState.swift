import AppKit
import SwiftUI
import KeyboardShortcuts

@Observable
@MainActor
final class AppState {
    let config = ConfigManager()
    let history = HistoryManager()
    let recorder = AudioRecorder()
    let transcriber = Transcriber()

    var showSettings = false
    var showHistory = false
    var statusText = "Ready"

    // The floating recording indicator panel
    private var floatingPanel: FloatingPanel?

    // Menubar icon name (SF Symbol) — changes based on state
    var menuBarIcon: String {
        if transcriber.isTranscribing { return "mic.badge.ellipsis" }
        if recorder.isRecording { return "record.circle.fill" }
        return "mic.circle"
    }

    init() {
        setupKeyboardShortcut()
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }
    }

    func toggle() {
        if recorder.isRecording {
            stopRecording()
        } else if !transcriber.isTranscribing {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.startRecording()
            statusText = "Recording..."
            showFloatingIndicator()
        } catch {
            NSLog("RecordToggle: startRecording error: \(error)")
            statusText = "Mic error: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        guard let url = recorder.stopRecording() else {
            statusText = "Too short"
            hideFloatingIndicator()
            return
        }

        _ = url  // URL is consumed by the transcriber via the recording file on disk

        hideFloatingIndicator()
        statusText = "Transcribing..."

        Task {
            do {
                let result = try await transcriber.transcribe(config: config)

                // Strip timestamps if user doesn't want them
                let clipboardText = config.includeTimestamps ? result : stripTimestamps(result)

                // Copy to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(clipboardText, forType: .string)

                // Auto-paste
                if config.autoPaste {
                    try? await Task.sleep(for: .milliseconds(300))
                    simulatePaste()
                }

                // Save to history and refresh
                history.save(result)
                history.refresh()
                statusText = "Done — copied to clipboard"

                // Reset status after delay
                try? await Task.sleep(for: .seconds(3))
                if statusText == "Done — copied to clipboard" {
                    statusText = "Ready"
                }
            } catch {
                NSLog("RecordToggle: transcription error: \(error)")
                statusText = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Floating Indicator

    private func showFloatingIndicator() {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 44))

        // Position at top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 100
            let y = screenFrame.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.show {
            RecordingIndicatorWrapper(recorder: self.recorder)
        }

        floatingPanel = panel
    }

    private func hideFloatingIndicator() {
        floatingPanel?.orderOut(nil)
        floatingPanel = nil
    }

    // MARK: - Auto-Paste

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            NSLog("RecordToggle: paste skipped — Accessibility not granted")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else {
            NSLog("RecordToggle: failed to create CGEvent")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        NSLog("RecordToggle: paste simulated via CGEvent")
    }

    /// Last result formatted according to user's timestamp preference
    var displayResult: String? {
        guard let result = transcriber.lastResult else { return nil }
        return config.includeTimestamps ? result : stripTimestamps(result)
    }

    func copyLastResult() {
        guard let result = transcriber.lastResult else { return }
        let text = config.includeTimestamps ? result : stripTimestamps(result)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "Copied"
    }

    /// Strips timestamp prefixes like "  [0.0s --> 2.3s] " and pause markers, returning plain text
    private func stripTimestamps(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Skip pause markers
            if trimmed.contains("[pause") { continue }
            // Strip timestamp prefix: [X.Xs --> X.Xs] text
            if let closingRange = trimmed.range(of: "] ", options: [],
                range: trimmed.startIndex..<trimmed.endIndex) {
                let afterBracket = String(trimmed[closingRange.upperBound...])
                if !afterBracket.isEmpty {
                    result.append(afterBracket)
                }
            } else {
                result.append(trimmed)
            }
        }
        return result.joined(separator: " ")
    }
}

// Wrapper to pass @Observable recorder to RecordingIndicator SwiftUI view
// This is needed because FloatingPanel.show uses @ViewBuilder
private struct RecordingIndicatorWrapper: View {
    let recorder: AudioRecorder

    var body: some View {
        RecordingIndicator(elapsedTime: recorder.elapsedTime, levels: recorder.levels)
    }
}
