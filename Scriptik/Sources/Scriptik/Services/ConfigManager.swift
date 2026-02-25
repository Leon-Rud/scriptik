import Foundation
import ServiceManagement
import SwiftUI

@Observable
@MainActor
final class ConfigManager {
    // MARK: - Config values with defaults

    var whisperModel = "medium"
    var pauseThreshold = 1.5
    var initialPrompt = ""
    var autoPaste = true
    var includeTimestamps = false
    var language = "auto"
    var whisperVenv: String
    var circlePositionX: Double = -1
    var circlePositionY: Double = -1
    var launchAtLogin: Bool = false {
        didSet {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    // MARK: - Path constants

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/scriptik")
    static let configFile = configDir.appendingPathComponent("config")
    static let historyDir = configDir.appendingPathComponent("history")
    static let dataDir = URL(fileURLWithPath: "/tmp/scriptik")
    static let pidFile = dataDir.appendingPathComponent("recording.pid")
    static let recordingFile = dataDir.appendingPathComponent("recording.wav")
    static let transcriptionFile = dataDir.appendingPathComponent("transcription.txt")

    // MARK: - Available options for settings UI

    static let availableModels = ["tiny", "base", "small", "medium", "large"]
    static let availableLanguages = ["auto", "en", "he"]

    // MARK: - Init

    init() {
        whisperVenv = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/scriptik/venv").path
        load()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Load config

    func load() {
        let path = Self.configFile.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Split on first '='
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eqIndex])
                .trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes (single or double)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }

            switch key {
            case "WHISPER_MODEL":
                whisperModel = value
            case "PAUSE_THRESHOLD":
                if let d = Double(value) { pauseThreshold = d }
            case "INITIAL_PROMPT":
                initialPrompt = value
            case "AUTO_PASTE":
                autoPaste = (value.lowercased() != "false" && value != "0")
            case "INCLUDE_TIMESTAMPS":
                includeTimestamps = (value.lowercased() != "false" && value != "0")
            case "LANGUAGE":
                language = value
            case "WHISPER_VENV":
                if !value.isEmpty { whisperVenv = value }
            case "CIRCLE_POSITION_X":
                if let d = Double(value) { circlePositionX = d }
            case "CIRCLE_POSITION_Y":
                if let d = Double(value) { circlePositionY = d }
            default:
                break
            }
        }
    }

    // MARK: - Save config

    func save() {
        let fm = FileManager.default
        let dirPath = Self.configDir.path

        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        var lines: [String] = []
        lines.append("# Scriptik configuration")
        lines.append("# This file is auto-generated. Manual edits are preserved.")
        lines.append("")
        lines.append("WHISPER_MODEL=\"\(whisperModel)\"")
        lines.append("PAUSE_THRESHOLD=\"\(pauseThreshold)\"")
        lines.append("INITIAL_PROMPT=\"\(initialPrompt)\"")
        lines.append("AUTO_PASTE=\"\(autoPaste)\"")
        lines.append("INCLUDE_TIMESTAMPS=\"\(includeTimestamps)\"")
        lines.append("LANGUAGE=\"\(language)\"")
        lines.append("WHISPER_VENV=\"\(whisperVenv)\"")
        lines.append("CIRCLE_POSITION_X=\"\(circlePositionX)\"")
        lines.append("CIRCLE_POSITION_Y=\"\(circlePositionY)\"")
        lines.append("")

        let content = lines.joined(separator: "\n")
        try? content.write(toFile: Self.configFile.path, atomically: true, encoding: .utf8)
    }

    // MARK: - Whisper Python path

    var whisperPython: String {
        let venvPython = (whisperVenv as NSString).appendingPathComponent("bin/python3")
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        // Fallback to ~/whisper-env
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("whisper-env/bin/python3").path
        return fallback
    }
}
