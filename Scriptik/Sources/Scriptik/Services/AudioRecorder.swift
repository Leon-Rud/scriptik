import Foundation
import AVFoundation

@Observable
@MainActor
final class AudioRecorder {
    var isRecording = false
    var currentLevel: Float = 0
    var levels: [Float] = Array(repeating: 0, count: 20)
    var elapsedTime: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var startTime: Date?

    // MARK: - Start recording

    func startRecording() throws {
        let fm = FileManager.default
        let dataDir = ConfigManager.dataDir.path

        // Create /tmp/scriptik/ if needed
        if !fm.fileExists(atPath: dataDir) {
            try fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        }

        // Remove old recording file
        let recordingPath = ConfigManager.recordingFile.path
        if fm.fileExists(atPath: recordingPath) {
            try fm.removeItem(atPath: recordingPath)
        }

        // Configure audio recorder settings for Whisper-compatible WAV
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let recorder = try AVAudioRecorder(url: ConfigManager.recordingFile, settings: settings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw RecorderError.failedToStart
        }

        audioRecorder = recorder

        // Write PID file to signal recording is active
        try "native".write(toFile: ConfigManager.pidFile.path, atomically: true, encoding: .utf8)

        // Track start time
        startTime = Date()
        isRecording = true

        // Start metering timer at ~20fps
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevels()
            }
        }
        // Ensure the timer fires during UI tracking (e.g., while menus are open)
        if let timer = levelTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Stop recording

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil

        levelTimer?.invalidate()
        levelTimer = nil

        // Remove PID file
        try? FileManager.default.removeItem(atPath: ConfigManager.pidFile.path)

        // Reset state
        isRecording = false
        currentLevel = 0
        levels = Array(repeating: 0, count: 20)
        elapsedTime = 0
        startTime = nil

        // Verify the recording file exists and has meaningful content
        let url = ConfigManager.recordingFile
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs[.size] as? Int) ?? 0
            // WAV header is ~44 bytes; require at least 1KB for usable audio
            guard size > 1024 else { return nil }
        } catch {
            return nil
        }

        return url
    }

    // MARK: - Private

    private func updateLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)

        // Normalize dB range (-50...0) to linear (0...1) with power curve
        // for more visible voice dynamics
        let linear = max(0, min(1, (power + 50) / 50))
        let normalized = pow(linear, 0.4)

        currentLevel = normalized

        // Shift levels array: drop oldest, append newest
        levels.removeFirst()
        levels.append(normalized)

        // Update elapsed time
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    // MARK: - Error

    enum RecorderError: LocalizedError {
        case failedToStart

        var errorDescription: String? {
            switch self {
            case .failedToStart:
                return "Failed to start audio recording. Check microphone permissions."
            }
        }
    }
}
