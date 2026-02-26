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
            Toggle("Launch at login", isOn: $config.launchAtLogin)

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
                ModelRow(
                    model: model,
                    isSelected: config.whisperModel == model.name
                ) {
                    config.whisperModel = model.name
                    config.save()
                }
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

            HStack {
                Text("Toggle Recording:")
                ShortcutRecorderView(name: .toggleRecording)
            }
            .padding()
        }
        .padding()
    }
}

// Custom shortcut recorder that avoids KeyboardShortcuts.Recorder's Bundle.module crash
// when running from an .app bundle (SPM resource bundle accessor can't find the
// KeyboardShortcuts localization bundle inside Contents/Resources/).
private struct ShortcutRecorderView: View {
    let name: KeyboardShortcuts.Name
    @State private var isRecording = false
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Text(displayText)
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 80)

            if currentShortcut != nil && !isRecording {
                Button {
                    KeyboardShortcuts.setShortcut(nil, for: name)
                    currentShortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onTapGesture { startRecording() }
        .onAppear { currentShortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear { stopRecording() }
    }

    private var displayText: String {
        if isRecording { return "Press shortcut…" }
        return currentShortcut.map { "\($0)" } ?? "Record Shortcut"
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        KeyboardShortcuts.disable(.toggleRecording)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            // Delete/Backspace clears the shortcut
            if event.keyCode == 51 || event.keyCode == 117 {
                KeyboardShortcuts.setShortcut(nil, for: name)
                currentShortcut = nil
                stopRecording()
                return nil
            }

            // Require at least one modifier (except for function keys)
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            let isFunctionKey = event.specialKey?.isFunctionKey == true

            guard !mods.subtracting(.shift).isEmpty || isFunctionKey else {
                NSSound.beep()
                return nil
            }

            if let shortcut = KeyboardShortcuts.Shortcut(event: event) {
                KeyboardShortcuts.setShortcut(shortcut, for: name)
                currentShortcut = shortcut
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        KeyboardShortcuts.enable(.toggleRecording)
    }
}

extension NSEvent.SpecialKey {
    fileprivate var isFunctionKey: Bool {
        let functionKeys: Set<NSEvent.SpecialKey> = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20
        ]
        return functionKeys.contains(self)
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Scriptik")
                .font(.title2)
                .fontWeight(.semibold)

            Text("v1.0.0")
                .foregroundStyle(.secondary)

            Text("Global audio recording with local Whisper transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("GitHub", destination: URL(string: "https://github.com/Leon-Rud/scriptik")!)
                .font(.caption)
        }
        .padding()
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: (name: String, size: String, speed: String, accuracy: String)
    let isSelected: Bool
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)

            VStack(alignment: .leading) {
                Text(model.name.capitalized)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(model.size) \u{2022} \(model.speed) \u{2022} \(model.accuracy)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
