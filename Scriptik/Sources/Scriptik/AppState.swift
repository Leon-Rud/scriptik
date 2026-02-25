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

    // Called with clipboard text when transcription finishes (used for toast)
    var onTranscriptionComplete: ((String) -> Void)?

    // The app that was active before recording started (for auto-paste)
    private var previousApp: NSRunningApplication?

    // Menubar icon name (SF Symbol) — changes based on state
    var menuBarIcon: String {
        if transcriber.isTranscribing { return "ellipsis.circle.fill" }
        if recorder.isRecording { return "record.circle.fill" }
        return "mic.circle"
    }

    init() {
        setupKeyboardShortcut()
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            // Capture the frontmost app immediately on the event handler thread,
            // before any async dispatch that might change focus
            let frontApp = NSWorkspace.shared.frontmostApplication
            Task { @MainActor in
                self?.toggle(capturedApp: frontApp)
            }
        }
    }

    func toggle(capturedApp: NSRunningApplication? = nil) {
        if recorder.isRecording {
            stopRecording()
        } else if !transcriber.isTranscribing {
            startRecording(capturedApp: capturedApp)
        }
    }

    private func startRecording(capturedApp: NSRunningApplication? = nil) {
        do {
            // Remember which app was active so we can paste into it later.
            // Use the captured app from the shortcut handler if available,
            // otherwise grab the current frontmost app (e.g. when triggered via UI button).
            let front = capturedApp ?? NSWorkspace.shared.frontmostApplication
            // Don't store Scriptik itself as the previous app
            if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = front
            }
            NSLog("Scriptik: previousApp = \(previousApp?.localizedName ?? "nil") (\(previousApp?.bundleIdentifier ?? "nil"))")
            playSound(.begin)
            try recorder.startRecording()
            statusText = "Recording..."
        } catch {
            NSLog("Scriptik: startRecording error: \(error)")
            statusText = "Mic error: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        playSound(.end)
        guard let url = recorder.stopRecording() else {
            statusText = "Too short"
            return
        }

        _ = url  // URL is consumed by the transcriber via the recording file on disk

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
                    await pasteIntoPreviousApp()
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
                NSLog("Scriptik: transcription error: \(error)")
                statusText = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Auto-Paste

    private var hasShownAccessibilityHint = false

    private func pasteIntoPreviousApp() async {
        guard let app = previousApp, !app.isTerminated else { return }

        // If Accessibility isn't granted, show a one-time hint but still try the paste
        if !AXIsProcessTrusted() && !hasShownAccessibilityHint {
            hasShownAccessibilityHint = true
            NSLog("Scriptik: Accessibility not granted — opening System Settings")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }

        let pid = app.processIdentifier
        let bundleId = app.bundleIdentifier ?? ""

        // Step 1: Bring target app to front
        if !bundleId.isEmpty {
            let openProc = Process()
            openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProc.arguments = ["-b", bundleId]
            try? openProc.run()
            openProc.waitUntilExit()
        } else {
            app.activate()
        }

        // Step 2: Wait for the app to actually become frontmost
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                break
            }
        }

        // Step 3: Extra settle time
        try? await Task.sleep(for: .milliseconds(200))

        // Step 4: Send Cmd+V via CGEvent
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Sound Feedback

    private enum SoundEvent { case begin, end }

    private func playSound(_ event: SoundEvent) {
        let soundName: String
        switch event {
        case .begin: soundName = "Ping"
        case .end:   soundName = "Purr"
        }
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.volume = 0.5
            sound.play()
        }
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
