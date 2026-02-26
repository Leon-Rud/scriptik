import AppKit
import SwiftUI

/// The persistent floating button always visible on screen.
/// Non-activating panel means it never steals focus from other apps.
struct FloatingCircleView: View {
    var appState: AppState
    @State private var pulseScale: CGFloat = 1.0
    @State private var iconPulse: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            // Pulsing glow ring when recording
            if appState.recorder.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                    .scaleEffect(pulseScale)
                    .opacity(Double(2.0 - pulseScale))
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: pulseScale
                    )
                    .onAppear { pulseScale = 1.4 }
                    .onDisappear { pulseScale = 1.0 }
            }

            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(bgColor.opacity(isHovered ? 0.8 : 0.6)))
                .shadow(color: appState.recorder.isRecording ? .red.opacity(0.5) : .black.opacity(isHovered ? 0.6 : 0.4),
                        radius: appState.recorder.isRecording ? 6 : (isHovered ? 6 : 4), x: 0, y: 2)
                .frame(width: 32, height: 32)

            centerContent
                .frame(width: 26, height: 26)
                .clipShape(Circle())
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .scaleEffect(isHovered ? 1.12 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.3), value: showCopied)
        .onHover { isHovered = $0 }
        .onTapGesture { appState.toggle() }
        .overlay(alignment: .topTrailing) {
            if appState.recorder.isRecording {
                CancelButton { appState.cancelRecording() }
                    .offset(x: 2, y: -2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.recorder.isRecording)
    }

    private var showCopied: Bool {
        appState.showCopiedFeedback && !appState.recorder.isRecording && !appState.transcriber.isTranscribing
    }

    @ViewBuilder
    private var centerContent: some View {
        if showCopied {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
        } else if appState.transcriber.isTranscribing {
            // Pulsing ellipsis
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(iconPulse ? 1.15 : 1.0)
                .opacity(iconPulse ? 0.7 : 1.0)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: iconPulse
                )
                .onAppear { iconPulse = true }
                .onDisappear { iconPulse = false }
        } else if appState.recorder.isRecording {
            VStack(spacing: 1) {
                WaveformView(
                    levels: appState.recorder.levels,
                    barCount: 5, barSpacing: 1.5,
                    minHeight: 1, maxHeight: 9,
                    color: .white,
                    mirror: true
                )
                .frame(height: 12)
                Text(formatTime(appState.recorder.elapsedTime))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
    }

    private var bgColor: Color {
        if showCopied { return .green }
        if appState.recorder.isRecording { return .red }
        if appState.transcriber.isTranscribing { return .orange }
        return Color(white: 0.15)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private struct CancelButton: View {
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.red : Color(white: 0.15))
                    .frame(width: 14, height: 14)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
