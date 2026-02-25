import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    var barCount: Int = 20
    var barSpacing: CGFloat = 2
    var minHeight: CGFloat = 2
    var maxHeight: CGFloat = 30
    var color: Color = .red
    var mirror: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(levels.suffix(barCount).enumerated()), id: \.offset) { index, level in
                let barHeight = minHeight + CGFloat(level) * (maxHeight - minHeight)
                capsuleBar(height: barHeight, level: level, index: index)
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels.map { Int($0 * 100) })
    }

    private func capsuleBar(height: CGFloat, level: Float, index: Int) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.5 + Double(level) * 0.5),
                        color.opacity(0.8 + Double(level) * 0.2)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: mirror ? height * 2 : height)
    }
}
