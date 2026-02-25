import AppKit
import SwiftUI

struct MainView: View {
    @Bindable var appState: AppState
    let openSettings: () -> Void
    let openHistory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer()

            // Center content
            VStack(spacing: 24) {
                statusIndicator

                waveformArea

                recordButton

                if appState.transcriber.isTranscribing {
                    transcribingIndicator
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Last result preview
            if let result = appState.displayResult, !result.isEmpty {
                resultCard(result)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 380)
        .frame(minHeight: 480)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button(action: openHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("History")

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Status

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(appState.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.statusText {
        case "Recording...": return .red
        case "Transcribing...": return .orange
        case "Done", "Copied": return .green
        case "Error", "Mic error": return .red
        default: return .secondary
        }
    }

    // MARK: - Waveform

    private var waveformArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.5))
                .frame(height: 80)

            if appState.recorder.isRecording {
                VStack(spacing: 8) {
                    WaveformView(
                        levels: appState.recorder.levels,
                        barCount: 30,
                        barSpacing: 3,
                        minHeight: 2,
                        maxHeight: 50,
                        color: .red,
                        mirror: true
                    )
                    .frame(height: 60)

                    Text(formatTime(appState.recorder.elapsedTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
            } else {
                WaveformView(
                    levels: Array(repeating: Float(0.05), count: 30),
                    barCount: 30,
                    barSpacing: 3,
                    minHeight: 2,
                    maxHeight: 50,
                    color: .secondary
                )
                .frame(height: 50)
                .opacity(0.3)
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: { appState.toggle() }) {
            HStack(spacing: 10) {
                Image(systemName: appState.recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title2)
                Text(appState.recorder.isRecording ? "Stop Recording" : "Start Recording")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.recorder.isRecording ? .red : .accentColor)
        .controlSize(.large)
        .disabled(appState.transcriber.isTranscribing)
    }

    // MARK: - Transcribing

    private var transcribingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result Card

    private func resultCard(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    appState.copyLastResult()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Text(result.prefix(300) + (result.count > 300 ? "..." : ""))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Set a global shortcut in Settings to record from anywhere")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
