import Foundation

@Observable
@MainActor
final class HistoryManager {
    struct Entry: Identifiable, Hashable {
        let id: String
        let filename: String
        let date: Date
        let content: String
        let preview: String
    }

    var entries: [Entry] = []

    // MARK: - Refresh

    func refresh() {
        let fm = FileManager.default
        let dirPath = ConfigManager.historyDir.path

        guard fm.fileExists(atPath: dirPath) else {
            entries = []
            return
        }

        guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else {
            entries = []
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var result: [Entry] = []

        for filename in files {
            guard filename.hasSuffix(".txt") else { continue }

            let nameWithoutExt = String(filename.dropLast(4)) // remove .txt
            guard let date = dateFormatter.date(from: nameWithoutExt) else { continue }

            let filePath = ConfigManager.historyDir.appendingPathComponent(filename).path
            let content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""

            let preview = extractPreview(from: content)

            let entry = Entry(
                id: nameWithoutExt,
                filename: filename,
                date: date,
                content: content,
                preview: preview
            )
            result.append(entry)
        }

        // Sort newest first
        result.sort { $0.date > $1.date }
        entries = result
    }

    // MARK: - Save new transcription

    func save(_ content: String) {
        let fm = FileManager.default
        let dirPath = ConfigManager.historyDir.path

        // Create history dir if needed
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let filename = formatter.string(from: Date()) + ".txt"

        let filePath = ConfigManager.historyDir.appendingPathComponent(filename).path
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Delete

    func delete(_ entry: Entry) {
        let filePath = ConfigManager.historyDir.appendingPathComponent(entry.filename).path
        try? FileManager.default.removeItem(atPath: filePath)
        entries.removeAll { $0.id == entry.id }
    }

    // MARK: - Total duration estimate

    var totalDuration: String {
        let totalSeconds = entries.count * 30 // ~30s average per entry
        let minutes = totalSeconds / 60
        if minutes < 1 {
            return "\(totalSeconds) sec"
        }
        return "\(minutes) min"
    }

    // MARK: - Private helpers

    private func extractPreview(from content: String) -> String {
        // Transcription format: "  [0.0s --> 2.3s] Some text here"
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip pause lines and empty lines
            if trimmed.isEmpty || trimmed.contains("[pause") { continue }
            // Look for lines with timestamp pattern [X.Xs --> X.Xs]
            guard trimmed.contains("-->") else { continue }

            // Extract text after the closing bracket of the timestamp
            // Format: [0.0s --> 2.3s] actual text
            if let arrowRange = trimmed.range(of: "-->"),
               let closingBracket = trimmed.range(of: "] ", options: [],
                range: arrowRange.upperBound..<trimmed.endIndex) {
                let text = String(trimmed[closingBracket.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if text.isEmpty { continue }
                if text.count > 80 {
                    return String(text.prefix(80)) + "..."
                }
                return text
            }
        }

        // Fallback: first non-empty line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if trimmed.count > 80 {
                    return String(trimmed.prefix(80)) + "..."
                }
                return trimmed
            }
        }

        return ""
    }
}
