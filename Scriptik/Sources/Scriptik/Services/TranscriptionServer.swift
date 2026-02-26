import Foundation

@Observable
@MainActor
final class TranscriptionServer {
    enum State: Equatable {
        case stopped
        case starting
        case ready
        case busy
    }

    private(set) var state: State = .stopped

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var lineBuffer = ""

    // Pending continuation for the current request (transcribe or reload)
    private var pendingContinuation: CheckedContinuation<[String: Any], Error>?

    // Continuation waiting for the "ready" signal on startup
    private var readyContinuation: CheckedContinuation<Void, Error>?

    private var currentModelName: String?

    // MARK: - Lifecycle

    func start(config: ConfigManager) {
        start(pythonPath: config.whisperPython, model: config.whisperModel)
    }

    func start(pythonPath: String, model: String) {
        guard state == .stopped else { return }
        state = .starting
        currentModelName = model

        guard let scriptPath = findServerScript() else {
            NSLog("Scriptik: transcribe_server.py not found")
            state = .stopped
            return
        }

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            NSLog("Scriptik: Python not found at \(pythonPath)")
            state = .stopped
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [scriptPath, model]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["LANG"] = "en_US.UTF-8"
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        let path = environment["PATH"] ?? ""
        if !path.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        }
        proc.environment = environment

        if let home = environment["HOME"] {
            proc.currentDirectoryURL = URL(fileURLWithPath: home)
        }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        process = proc

        // Read stdout asynchronously
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let str = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.handleOutput(str)
            }
        }

        // Log stderr
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                NSLog("Scriptik server stderr: %@", str.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Handle unexpected termination
        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.handleTermination(exitCode: proc.terminationStatus)
            }
        }

        do {
            try proc.run()
            NSLog("Scriptik: server process launched (pid %d, model: %@)", proc.processIdentifier, model)

            // Wait for ready signal
            Task {
                do {
                    try await waitForReady(timeout: 30)
                    NSLog("Scriptik: server ready (model: %@, pid: %d)", model, proc.processIdentifier)
                } catch {
                    NSLog("Scriptik: server failed to become ready: %@", error.localizedDescription)
                    stop()
                }
            }
        } catch {
            NSLog("Scriptik: failed to launch server: %@", error.localizedDescription)
            state = .stopped
        }
    }

    func stop() {
        let proc = process
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        lineBuffer = ""
        state = .stopped

        // Cancel any pending continuations
        readyContinuation?.resume(throwing: CancellationError())
        readyContinuation = nil
        pendingContinuation?.resume(throwing: CancellationError())
        pendingContinuation = nil

        if let proc, proc.isRunning {
            proc.terminate()
            NSLog("Scriptik: server process terminated")
        }
    }

    // MARK: - Transcription

    func transcribe(
        recordingPath: String,
        transcriptionPath: String,
        pauseThreshold: Double,
        model: String,
        initialPrompt: String,
        language: String
    ) async throws -> String {
        guard state == .ready || state == .starting else {
            throw TranscriptionServerError.notReady
        }

        // Wait for ready if still starting
        if state == .starting {
            try await waitForReady(timeout: 30)
        }

        state = .busy
        defer { if state == .busy { state = .ready } }

        let request: [String: Any] = [
            "type": "transcribe",
            "recording_path": recordingPath,
            "transcription_path": transcriptionPath,
            "pause_threshold": pauseThreshold,
            "model": model,
            "initial_prompt": initialPrompt,
            "language": language,
        ]

        let response = try await sendRequest(request, timeout: 120)

        guard let type = response["type"] as? String else {
            throw TranscriptionServerError.invalidResponse
        }

        if type == "error" {
            let message = response["message"] as? String ?? "Unknown server error"
            throw TranscriptionServerError.serverError(message)
        }

        guard type == "transcription_done" else {
            throw TranscriptionServerError.invalidResponse
        }

        // The server writes the file; read it back (same as one-shot path)
        let content = try String(contentsOfFile: transcriptionPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if content.isEmpty {
            throw TranscriptionServerError.noOutput
        }

        return content
    }

    // MARK: - Model Reload

    func reloadModel(_ model: String) {
        guard state == .ready else { return }
        currentModelName = model
        state = .busy

        Task {
            do {
                let request: [String: Any] = ["type": "reload_model", "model": model]
                let response = try await sendRequest(request, timeout: 60)
                let type = response["type"] as? String
                if type == "model_reloaded" {
                    NSLog("Scriptik: server reloaded model to %@", model)
                } else if type == "error" {
                    NSLog("Scriptik: server reload error: %@", response["message"] as? String ?? "?")
                }
                state = .ready
            } catch {
                NSLog("Scriptik: model reload failed: %@", error.localizedDescription)
                state = .ready
            }
        }
    }

    // MARK: - Private

    private func sendRequest(_ request: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let stdinPipe else { throw TranscriptionServerError.notReady }

        let data = try JSONSerialization.data(withJSONObject: request)
        guard var jsonLine = String(data: data, encoding: .utf8) else {
            throw TranscriptionServerError.invalidResponse
        }
        jsonLine += "\n"

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation

            stdinPipe.fileHandleForWriting.write(jsonLine.data(using: .utf8)!)

            // Timeout
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let cont = pendingContinuation {
                    pendingContinuation = nil
                    cont.resume(throwing: TranscriptionServerError.timeout)
                }
            }
        }
    }

    private func waitForReady(timeout: TimeInterval) async throws {
        guard state == .starting else {
            if state == .ready { return }
            throw TranscriptionServerError.notReady
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let cont = readyContinuation {
                    readyContinuation = nil
                    cont.resume(throwing: TranscriptionServerError.timeout)
                }
            }
        }
    }

    private func handleOutput(_ str: String) {
        lineBuffer += str

        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else {
                NSLog("Scriptik server: unparseable line: %@", line)
                continue
            }

            switch type {
            case "ready":
                state = .ready
                readyContinuation?.resume()
                readyContinuation = nil

            case "pong":
                pendingContinuation?.resume(returning: json)
                pendingContinuation = nil

            case "transcription_done", "model_reloaded", "error":
                pendingContinuation?.resume(returning: json)
                pendingContinuation = nil

            default:
                NSLog("Scriptik server: unknown response type: %@", type)
            }
        }
    }

    private func handleTermination(exitCode: Int32) {
        NSLog("Scriptik: server process terminated with code %d", exitCode)

        let wasRunning = state != .stopped
        let modelName = currentModelName ?? "medium"

        // Resume any pending continuations with error
        readyContinuation?.resume(throwing: TranscriptionServerError.processTerminated)
        readyContinuation = nil
        pendingContinuation?.resume(throwing: TranscriptionServerError.processTerminated)
        pendingContinuation = nil

        state = .stopped
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        lineBuffer = ""

        // Auto-restart if it was running (not an explicit stop)
        if wasRunning {
            NSLog("Scriptik: auto-restarting server in 500ms")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                // Find python path from default venv location
                let pythonPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local/share/scriptik/venv/bin/python3").path
                if FileManager.default.fileExists(atPath: pythonPath) {
                    self.start(pythonPath: pythonPath, model: modelName)
                }
            }
        }
    }

    private func findServerScript() -> String? {
        // 1. Main bundle resource
        if let url = Bundle.main.url(forResource: "transcribe_server", withExtension: "py") {
            return url.path
        }

        // 2. Nested bundle (SPM resource bundle)
        let nestedPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Scriptik_Scriptik.bundle/transcribe_server.py")
        if FileManager.default.fileExists(atPath: nestedPath.path) {
            return nestedPath.path
        }

        // 3. Development fallback
        let executableURL = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let devPath = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("transcribe_server.py")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }

        // 4. Source tree fallback
        let sourcePath = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/transcribe_server.py")
        if FileManager.default.fileExists(atPath: sourcePath.path) {
            return sourcePath.path
        }

        return nil
    }

    // MARK: - Errors

    enum TranscriptionServerError: LocalizedError {
        case notReady
        case timeout
        case processTerminated
        case invalidResponse
        case serverError(String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .notReady: return "Transcription server is not ready."
            case .timeout: return "Transcription server timed out."
            case .processTerminated: return "Transcription server process terminated unexpectedly."
            case .invalidResponse: return "Invalid response from transcription server."
            case .serverError(let msg): return "Server error: \(msg)"
            case .noOutput: return "Transcription produced no output."
            }
        }
    }
}
