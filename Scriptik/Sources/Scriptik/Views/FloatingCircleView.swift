import AppKit
import SwiftUI

/// The persistent floating button always visible on screen.
/// Non-activating panel means it never steals focus from other apps.
struct FloatingCircleView: View {
    var appState: AppState
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseScale2: CGFloat = 1.0
    @State private var isBreathing: Bool = false
    @State private var isHovered: Bool = false

    // Circle sizes
    private let circleSize: CGFloat = 32
    private let outerFrame: CGFloat = 56  // Enough room for pulse + X button

    var body: some View {
        ZStack {
            // Pulsing glow rings when recording (two staggered rings)
            if appState.recorder.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.50), lineWidth: 1.5)
                    .frame(width: circleSize, height: circleSize)
                    .scaleEffect(pulseScale)
                    .opacity(Double(2.0 - pulseScale))
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: pulseScale
                    )
                    .onAppear { pulseScale = 1.5 }
                    .onDisappear { pulseScale = 1.0 }

                Circle()
                    .stroke(Color.red.opacity(0.30), lineWidth: 1.0)
                    .frame(width: circleSize, height: circleSize)
                    .scaleEffect(pulseScale2)
                    .opacity(Double(2.0 - pulseScale2))
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.6),
                        value: pulseScale2
                    )
                    .onAppear { pulseScale2 = 1.5 }
                    .onDisappear { pulseScale2 = 1.0 }
            }

            // Breathing glow when transcribing
            if appState.transcriber.isTranscribing {
                Circle()
                    .fill(Color.indigo.opacity(0.20))
                    .frame(width: circleSize + 8, height: circleSize + 8)
                    .scaleEffect(isBreathing ? 1.3 : 1.0)
                    .opacity(isBreathing ? 0.0 : 0.40)
                    .blur(radius: 2)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isBreathing
                    )
                    .onAppear { isBreathing = true }
                    .onDisappear { isBreathing = false }
            }

            // Main circle — glass morphism base
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(bgColor.opacity(isHovered ? 0.8 : 0.6)))
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 2)
                .frame(width: circleSize, height: circleSize)
                .scaleEffect(transcribingBreathScale)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                           value: isBreathing)

            centerContent
                .frame(width: 26, height: 26)
                .scaleEffect(transcribingBreathScale)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                           value: isBreathing)

            // X cancel button — inside the ZStack so it's not clipped by overlay bounds
            if appState.recorder.isRecording {
                CancelButton { appState.cancelRecording() }
                    .offset(x: circleSize / 2 - 2, y: -(circleSize / 2 - 2))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: outerFrame, height: outerFrame)
        .contentShape(Circle())
        .scaleEffect(isHovered ? 1.12 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.3), value: showCopied)
        .animation(.easeInOut(duration: 0.2), value: appState.recorder.isRecording)
        .onHover { isHovered = $0 }
        .onTapGesture { appState.toggle() }
    }

    // MARK: - Derived State

    private var showCopied: Bool {
        appState.showCopiedFeedback && !appState.recorder.isRecording && !appState.transcriber.isTranscribing
    }

    private var transcribingBreathScale: CGFloat {
        appState.transcriber.isTranscribing && isBreathing ? 1.04 : 1.0
    }

    private var shadowColor: Color {
        if appState.recorder.isRecording { return .red.opacity(0.5) }
        if appState.transcriber.isTranscribing { return .indigo.opacity(0.4) }
        return .black.opacity(isHovered ? 0.6 : 0.4)
    }

    private var shadowRadius: CGFloat {
        if appState.recorder.isRecording { return 6 }
        if appState.transcriber.isTranscribing { return 5 }
        return isHovered ? 6 : 4
    }

    // MARK: - Center Content

    @ViewBuilder
    private var centerContent: some View {
        if showCopied {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
        } else if appState.transcriber.isTranscribing {
            // Progress ring only
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)

                // Progress fill
                Circle()
                    .trim(from: 0, to: appState.transcriptionProgress)
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: appState.transcriptionProgress)
            }
        } else if appState.recorder.isRecording {
            VStack(spacing: 1) {
                WaveformView(
                    levels: appState.recorder.levels,
                    barCount: 5, barSpacing: 1.5,
                    minHeight: 2, maxHeight: 8,
                    color: .white,
                    mirror: true
                )
                .frame(width: 24, height: 16)
                .clipped()
                Text(formatTime(appState.recorder.elapsedTime))
                    .font(.system(size: 6, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    private var bgColor: Color {
        if showCopied { return .green }
        if appState.recorder.isRecording { return .red }
        if appState.transcriber.isTranscribing { return .indigo }
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
