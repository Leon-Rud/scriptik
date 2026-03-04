import AppKit
import AVFoundation
import SwiftUI
import KeyboardShortcuts

@Observable
@MainActor
final class AppState {
    let config = ConfigManager()
    let history = HistoryManager()
    let recorder = AudioRecorder()
    let transcriber = Transcriber()
    let transcriptionServer = TranscriptionServer()

    var showSettings = false
    var showHistory = false
    var statusText = "Ready"
    var showCopiedFeedback = false

    // Transcription progress (0.0–1.0) and elapsed time
    var transcriptionProgress: Double = 0
    var transcriptionElapsed: TimeInterval = 0

    // The app that was active before recording started (for auto-paste)
    private var previousApp: NSRunningApplication?

    // Progress estimation state
    private var lastRecordingDuration: TimeInterval = 0
    private var estimatedTranscriptionDuration: TimeInterval = 0
    private var transcriptionStartTime: Date?
    private var progressTimer: Timer?

    // Menubar icon name (SF Symbol) — changes based on state
    var menuBarIcon: String {
        if transcriber.isTranscribing { return "ellipsis.circle.fill" }
        if recorder.isRecording { return "record.circle.fill" }
        return "mic.circle"
    }

    init() {
        setupKeyboardShortcut()
        transcriptionServer.start(config: config)
        requestPermissionsOnFirstLaunch()
    }

    // MARK: - Permission Status

    var isMicrophoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            NSLog("Scriptik: microphone permission \(granted ? "granted" : "denied")")
        }
    }

    /// Prompt for microphone and accessibility permissions on first launch
    /// so the user grants them before their first recording.
    private func requestPermissionsOnFirstLaunch() {
        // Microphone: triggers the system dialog if not yet determined
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            NSLog("Scriptik: microphone permission \(granted ? "granted" : "denied")")
        }

        // Accessibility: only prompt once via system dialog (tracked in UserDefaults).
        // After the first prompt, we check silently and guide through Settings UI instead.
        let hasRequested = UserDefaults.standard.bool(forKey: "hasRequestedAccessibility")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): !hasRequested] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !hasRequested {
            UserDefaults.standard.set(true, forKey: "hasRequestedAccessibility")
        }
        NSLog("Scriptik: accessibility trusted = \(trusted)")
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

        // Capture recording duration before stopping
        lastRecordingDuration = recorder.elapsedTime

        guard let url = recorder.stopRecording() else {
            statusText = "Too short"
            return
        }

        _ = url  // URL is consumed by the transcriber via the recording file on disk

        statusText = "Transcribing..."
        startProgressTimer()

        Task {
            do {
                let result = try await transcriber.transcribe(config: config, server: transcriptionServer)
                stopProgressTimer()

                // Strip timestamps if user doesn't want them
                let clipboardText = config.includeTimestamps ? result : stripTimestamps(result)

                // Copy to clipboard (plain text + HTML for broad app compatibility)
                writeToClipboard(clipboardText)

                // Auto-paste
                if config.autoPaste {
                    try? await Task.sleep(for: .milliseconds(300))
                    await pasteIntoPreviousApp()
                }

                // Save to history and refresh
                history.save(result)
                history.refresh()
                // Keep accessibility warning if it was set by pasteIntoPreviousApp,
                // otherwise show the normal success message
                if !statusText.contains("Accessibility") {
                    statusText = "Done — copied to clipboard"
                }
                triggerCopiedFeedback()

                // Reset status after delay
                let currentStatus = statusText
                try? await Task.sleep(for: .seconds(3))
                if statusText == currentStatus {
                    statusText = "Ready"
                }
            } catch {
                stopProgressTimer()
                NSLog("Scriptik: transcription error: \(error)")
                statusText = "Error: \(error.localizedDescription)"
            }
        }
    }

    func modelDidChange() {
        transcriptionServer.reloadModel(config.whisperModel)
    }

    func cancelRecording() {
        guard recorder.isRecording else { return }
        playSound(.cancel)
        _ = recorder.stopRecording()
        // Delete the recording file
        try? FileManager.default.removeItem(at: ConfigManager.recordingFile)
        statusText = "Cancelled"
        Task {
            try? await Task.sleep(for: .seconds(2))
            if statusText == "Cancelled" { statusText = "Ready" }
        }
    }

    // MARK: - Progress Estimation

    private func startProgressTimer() {
        estimatedTranscriptionDuration = Transcriber.estimatedDuration(
            recordingDuration: lastRecordingDuration, model: config.whisperModel
        )
        transcriptionStartTime = Date()
        transcriptionProgress = 0
        transcriptionElapsed = 0

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
        if let timer = progressTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateProgress() {
        guard let start = transcriptionStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        transcriptionElapsed = elapsed

        // Asymptotic curve: approaches 1.0 but never reaches it
        // At t = estimated, progress ≈ 0.92
        let ratio = elapsed / estimatedTranscriptionDuration
        transcriptionProgress = 1.0 - exp(-2.5 * ratio)
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        transcriptionProgress = 0
        transcriptionElapsed = 0
        transcriptionStartTime = nil
        estimatedTranscriptionDuration = 0
    }

    /// Estimated seconds remaining for the current transcription.
    var estimatedTimeRemaining: TimeInterval {
        guard estimatedTranscriptionDuration > 0 else { return 0 }
        return max(0, estimatedTranscriptionDuration - transcriptionElapsed)
    }

    // MARK: - Auto-Paste

    private func pasteIntoPreviousApp() async {
        guard let app = previousApp, !app.isTerminated else {
            NSLog("Scriptik: auto-paste skipped — no previous app or terminated")
            return
        }

        // Accessibility permission is required to post keyboard events to other apps.
        // Check silently — the onboarding prompt was already shown on first launch.
        // If not granted, show a helpful status message instead of failing silently.
        if !AXIsProcessTrusted() {
            NSLog("Scriptik: auto-paste skipped — accessibility not granted")
            statusText = "Copied — enable Accessibility for auto-paste"
            return
        }

        let pid = app.processIdentifier
        NSLog("Scriptik: activating \(app.localizedName ?? "?") (pid \(pid)) for paste")

        // Step 1: Activate target app (non-blocking, matches AudioWhisper approach)
        app.activate()

        // Step 2: Wait for activation via notification (event-driven, 2s timeout)
        let activated = await waitForActivation(pid: pid, timeout: 2.0)
        if !activated {
            NSLog("Scriptik: target app did not become frontmost within timeout")
        }

        // Step 3: Settle time
        try? await Task.sleep(for: .milliseconds(150))

        // Step 4: Verify pasteboard has our text before pasting
        let pb = NSPasteboard.general
        let expected = pb.string(forType: .string)
        if expected == nil || expected!.isEmpty {
            NSLog("Scriptik: pasteboard empty, skipping paste")
            return
        }

        // Step 5: Send Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        NSLog("Scriptik: Cmd+V posted to \(app.localizedName ?? "?")")
    }

    private func waitForActivation(pid: pid_t, timeout: TimeInterval) async -> Bool {
        // If already frontmost, return immediately
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            return true
        }

        // Wait for didActivateApplicationNotification
        return await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            let timer = DispatchSource.makeTimerSource(queue: .main)

            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { note in
                if let activated = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication),
                   activated.processIdentifier == pid {
                    timer.cancel()
                    if let obs = observer { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
                    continuation.resume(returning: true)
                }
            }

            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if let obs = observer { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
                continuation.resume(returning: false)
            }
            timer.resume()
        }
    }

    // MARK: - Sound Feedback

    private enum SoundEvent { case begin, end, cancel }

    private func playSound(_ event: SoundEvent) {
        guard config.enableSoundFeedback else { return }
        let soundName: String
        switch event {
        case .begin:  soundName = "Ping"
        case .end:    soundName = "Purr"
        case .cancel: soundName = "Funk"
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
        writeToClipboard(text)
        statusText = "Copied"
        triggerCopiedFeedback()
    }

    private func triggerCopiedFeedback() {
        showCopiedFeedback = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            showCopiedFeedback = false
        }
    }

    /// Writes text to clipboard with both plain-text and HTML representations.
    /// Plain text (with LTR mark) serves native macOS apps.
    /// HTML (with dir="ltr") serves Electron/web-based apps like Cursor.
    private func writeToClipboard(_ text: String) {
        let htmlBody = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
        let html = "<div dir=\"ltr\" style=\"white-space: pre-wrap;\">\(htmlBody)</div>"

        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(html, forType: .html)
        NSPasteboard.general.writeObjects([item])
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
