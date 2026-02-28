import AVFoundation
import SwiftUI
import KeyboardShortcuts

// Register the keyboard shortcut name
extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

struct SettingsView: View {
    @Bindable var config: ConfigManager
    var appState: AppState?
    var onModelChange: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var allPermissionsGranted: Bool
    @State private var permissionTimer: Timer?

    init(config: ConfigManager, appState: AppState? = nil, onModelChange: (() -> Void)? = nil) {
        self.config = config
        self.appState = appState
        self.onModelChange = onModelChange
        let granted = appState == nil || (appState!.isMicrophoneGranted && appState!.isAccessibilityGranted)
        self._allPermissionsGranted = State(initialValue: granted)
    }

    var body: some View {
        Group {
            if let appState, !allPermissionsGranted {
                PermissionsSetupView(appState: appState, allGranted: $allPermissionsGranted)
            } else {
                TabView {
                    GeneralTab(config: config)
                        .tabItem { Label("General", systemImage: "gear") }

                    ModelTab(config: config, onModelChange: onModelChange)
                        .tabItem { Label("Model", systemImage: "cpu") }

                    ShortcutTab()
                        .tabItem { Label("Shortcut", systemImage: "command") }

                    if let appState {
                        PermissionsTab(appState: appState)
                            .tabItem { Label("Permissions", systemImage: "lock.shield") }
                    }

                    AboutTab()
                        .tabItem { Label("About", systemImage: "info.circle") }
                }
            }
        }
        .frame(width: 420, height: 440)
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

            Toggle("Show floating circle button", isOn: $config.showFloatingCircle)

            Toggle("Auto-paste after transcription", isOn: $config.autoPaste)

            Toggle("Include timestamps in output", isOn: $config.includeTimestamps)

            Toggle("Play sound feedback", isOn: $config.enableSoundFeedback)

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
    var onModelChange: (() -> Void)?

    private let modelInfo: [(name: String, size: String, speed: String, accuracy: String)] = [
        ("tiny", "75 MB", "~1s", "Basic"),
        ("base", "140 MB", "~2s", "Good"),
        ("small", "500 MB", "~5s", "Great"),
        ("medium", "1.5 GB", "~15s", "Excellent"),
        ("large", "3 GB", "~30s", "Best"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper Model")
                        .font(.headline)
                    Text("Choose the model for speech recognition. Larger models are more accurate but slower.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(modelInfo, id: \.name) { model in
                ModelRow(
                    model: model,
                    isSelected: config.whisperModel == model.name,
                    isRecommended: model.name == "medium"
                ) {
                    config.whisperModel = model.name
                    config.save()
                    onModelChange?()
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

// MARK: - Permissions Setup (shown before full settings are unlocked)

private struct PermissionsSetupView: View {
    let appState: AppState
    @Binding var allGranted: Bool
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Welcome to Scriptik")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Grant these permissions to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                PermissionRow(
                    name: "Microphone",
                    description: "Required to record audio for transcription.",
                    icon: "mic.fill",
                    isGranted: micGranted,
                    action: {
                        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                            appState.requestMicrophonePermission()
                        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )

                PermissionRow(
                    name: "Accessibility",
                    description: "Required for auto-paste (simulates Cmd+V). Scriptik does not read your keystrokes.",
                    icon: "accessibility",
                    isGranted: accessibilityGranted,
                    action: { appState.openAccessibilitySettings() }
                )
            }
            .padding(.horizontal)

            if micGranted && !accessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("After enabling in System Settings, this will update automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear { refreshPermissions(); startAutoRefresh() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private func refreshPermissions() {
        micGranted = appState.isMicrophoneGranted
        accessibilityGranted = appState.isAccessibilityGranted
        if micGranted && accessibilityGranted {
            refreshTimer?.invalidate()
            allGranted = true
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in refreshPermissions() }
        }
    }
}

// MARK: - Permissions Tab

private struct PermissionsTab: View {
    let appState: AppState
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions")
                        .font(.headline)
                    Text("Scriptik needs these permissions to record and auto-paste.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PermissionRow(
                name: "Microphone",
                description: "Required to record audio for transcription.",
                icon: "mic.fill",
                isGranted: micGranted,
                action: {
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                        appState.requestMicrophonePermission()
                    } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            PermissionRow(
                name: "Accessibility",
                description: "Required for auto-paste (simulates Cmd+V). Scriptik does not read your keystrokes.",
                icon: "accessibility",
                isGranted: accessibilityGranted,
                action: { appState.openAccessibilitySettings() }
            )

            if !accessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("After enabling in System Settings, click Recheck or relaunch Scriptik.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Button("Recheck Permissions") {
                    refreshPermissions()
                }
                .controlSize(.small)
            }
        }
        .padding()
        .onAppear { refreshPermissions(); startAutoRefresh() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private func refreshPermissions() {
        micGranted = appState.isMicrophoneGranted
        accessibilityGranted = appState.isAccessibilityGranted
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in refreshPermissions() }
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let description: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(isGranted ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text(name)
                        .fontWeight(.medium)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isGranted {
                Button("Open Settings") {
                    action()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGranted ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        )
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

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
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
    var isRecommended: Bool = false
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name.capitalized)
                        .fontWeight(isSelected ? .semibold : .regular)

                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                }
                Text("\(model.size) \u{2022} \(model.speed) \u{2022} \(model.accuracy)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.08) : isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
