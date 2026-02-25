import SwiftUI

struct RecordingIndicator: View {
    let elapsedTime: TimeInterval
    let levels: [Float]
    @State private var appear = false

    var body: some View {
        ZStack {
            // Blurred dark circle background
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.black.opacity(0.45)))

            VStack(spacing: 6) {
                // Animated waveform
                WaveformView(
                    levels: levels,
                    barCount: 10,
                    barSpacing: 2.5,
                    minHeight: 3,
                    maxHeight: 28,
                    color: .red
                )
                .frame(height: 32)

                // Elapsed time
                Text(formatTime(elapsedTime))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 100, height: 100)
        .scaleEffect(appear ? 1 : 0.7)
        .opacity(appear ? 1 : 0)
        .animation(.spring(duration: 0.3), value: appear)
        .onAppear { appear = true }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
