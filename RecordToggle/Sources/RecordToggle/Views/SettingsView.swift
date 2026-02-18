import SwiftUI
import KeyboardShortcuts

// Register the keyboard shortcut name
extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

struct SettingsView: View {
    @Bindable var config: ConfigManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            GeneralTab(config: config)
                .tabItem { Label("General", systemImage: "gear") }

            ModelTab(config: config)
                .tabItem { Label("Model", systemImage: "cpu") }

            ShortcutTab()
                .tabItem { Label("Shortcut", systemImage: "command") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 300)
        .onDisappear { config.save() }
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Bindable var config: ConfigManager

    var body: some View {
        Form {
            Picker("Language", selection: $config.language) {
                ForEach(ConfigManager.availableLanguages, id: \.self) { lang in
                    Text(languageLabel(lang)).tag(lang)
                }
            }

            Toggle("Auto-paste after transcription", isOn: $config.autoPaste)

            Toggle("Include timestamps in output", isOn: $config.includeTimestamps)

            TextField("Initial prompt (hint words)", text: $config.initialPrompt, axis: .vertical)
                .lineLimit(2...4)

            HStack {
                Text("Pause threshold")
                Slider(value: $config.pauseThreshold, in: 0.5...5.0, step: 0.1)
                Text(String(format: "%.1fs", config.pauseThreshold))
                    .monospacedDigit()
                    .frame(width: 35)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "auto": return "Auto-detect"
        case "en": return "English"
        case "he": return "Hebrew"
        default: return code
        }
    }
}

// MARK: - Model Tab

private struct ModelTab: View {
    @Bindable var config: ConfigManager

    private let modelInfo: [(name: String, size: String, speed: String, accuracy: String)] = [
        ("tiny", "75 MB", "~1s", "Basic"),
        ("base", "140 MB", "~2s", "Good"),
        ("small", "500 MB", "~5s", "Great"),
        ("medium", "1.5 GB", "~15s", "Excellent"),
        ("large", "3 GB", "~30s", "Best"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whisper Model")
                .font(.headline)

            ForEach(modelInfo, id: \.name) { model in
                HStack {
                    Image(systemName: config.whisperModel == model.name ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(config.whisperModel == model.name ? .blue : .secondary)

                    VStack(alignment: .leading) {
                        Text(model.name.capitalized)
                            .fontWeight(config.whisperModel == model.name ? .semibold : .regular)
                        Text("\(model.size) \u{2022} \(model.speed) \u{2022} \(model.accuracy)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    config.whisperModel = model.name
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
    }
}

// MARK: - Shortcut Tab

private struct ShortcutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Global Shortcut")
                .font(.headline)

            Text("Press your preferred key combination to toggle recording from any app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)
                .padding()
        }
        .padding()
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Record Toggle")
                .font(.title2)
                .fontWeight(.semibold)

            Text("v1.0.0")
                .foregroundStyle(.secondary)

            Text("Global audio recording with local Whisper transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("GitHub", destination: URL(string: "https://github.com/Leon-Rud/record-toggle")!)
                .font(.caption)
        }
        .padding()
    }
}
