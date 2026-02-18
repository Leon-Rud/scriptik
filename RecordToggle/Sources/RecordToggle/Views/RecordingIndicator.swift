import SwiftUI

struct RecordingIndicator: View {
    let elapsedTime: TimeInterval
    let levels: [Float]
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)

            // Timer
            Text(formatTime(elapsedTime))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)

            // Mini waveform
            WaveformView(levels: levels, barCount: 12, barSpacing: 1.5, minHeight: 2, maxHeight: 16, color: .red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .onAppear { isPulsing = true }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
