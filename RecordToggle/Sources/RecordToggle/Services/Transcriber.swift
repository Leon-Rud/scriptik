import Foundation

@Observable
@MainActor
final class Transcriber {
    var isTranscribing = false
    var lastResult: String?

    // MARK: - Error types

    enum TranscriberError: LocalizedError {
        case scriptNotFound
        case whisperNotInstalled
        case processFailed(String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .scriptNotFound:
                return "Could not find transcribe.py script in app bundle."
            case .whisperNotInstalled:
                return "Whisper Python environment not found. Please run the setup script."
            case .processFailed(let detail):
                return "Transcription failed: \(detail)"
            case .noOutput:
                return "Transcription produced no output."
            }
        }
    }

    // MARK: - Transcribe

    func transcribe(config: ConfigManager) async throws -> String {
        isTranscribing = true

        do {
            let result = try await runTranscription(config: config)
            lastResult = result
            isTranscribing = false
            return result
        } catch {
            isTranscribing = false
            throw error
        }
    }

    // MARK: - Private

    private func runTranscription(config: ConfigManager) async throws -> String {
        // Locate transcribe.py script
        let scriptPath = try findScript()

        // Verify Python environment exists
        let pythonPath = config.whisperPython
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw TranscriberError.whisperNotInstalled
        }

        let recordingPath = ConfigManager.recordingFile.path
        let transcriptionPath = ConfigManager.transcriptionFile.path

        // Remove any stale transcription output
        try? FileManager.default.removeItem(atPath: transcriptionPath)

        // Build arguments
        let arguments = [
            scriptPath,
            recordingPath,
            transcriptionPath,
            String(config.pauseThreshold),
            config.whisperModel,
            config.initialPrompt,
            config.language,
        ]

        // Inherit current environment so ffmpeg and other tools are on PATH
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["LANG"] = "en_US.UTF-8"
        // Force-set HOME (macOS apps launched via `open` may not have it,
        // which breaks Python's os.path.expanduser("~") and Whisper's model cache)
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        // Ensure Homebrew paths are included (ffmpeg is often here)
        let path = environment["PATH"] ?? ""
        if !path.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        }

        // Run the process on a background thread
        let (exitCode, stderrOutput) = try await Task.detached { @Sendable () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = arguments
            process.environment = environment
            // Set working dir to HOME (default is / which is read-only on macOS)
            if let home = environment["HOME"] {
                process.currentDirectoryURL = URL(fileURLWithPath: home)
            }

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            // Discard stdout
            process.standardOutput = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return (process.terminationStatus, stderr)
        }.value

        // Check exit status
        if exitCode != 0 {
            let detail = stderrOutput.isEmpty
                ? "Process exited with code \(exitCode)"
                : stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriberError.processFailed(detail)
        }

        // Read transcription output
        guard FileManager.default.fileExists(atPath: transcriptionPath) else {
            throw TranscriberError.noOutput
        }

        let content = try String(contentsOfFile: transcriptionPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if content.isEmpty {
            throw TranscriberError.noOutput
        }

        return content
    }

    private func findScript() throws -> String {
        // 1. Check main bundle resource
        if let url = Bundle.main.url(forResource: "transcribe", withExtension: "py") {
            return url.path
        }

        // 2. Check nested bundle (SPM resource bundle inside app)
        let nestedPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/RecordToggle_RecordToggle.bundle/transcribe.py")
        if FileManager.default.fileExists(atPath: nestedPath.path) {
            return nestedPath.path
        }

        // 3. Development fallback: look relative to the executable
        let executableURL = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let devPath = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("transcribe.py")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }

        // 4. Another development fallback: look in the source tree
        let sourcePath = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/transcribe.py")
        if FileManager.default.fileExists(atPath: sourcePath.path) {
            return sourcePath.path
        }

        throw TranscriberError.scriptNotFound
    }
}
