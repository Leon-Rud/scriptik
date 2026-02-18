import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    var barCount: Int = 20
    var barSpacing: CGFloat = 2
    var minHeight: CGFloat = 2
    var maxHeight: CGFloat = 30
    var color: Color = .red

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(levels.suffix(barCount).enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.6 + Double(level) * 0.4))
                    .frame(
                        width: 3,
                        height: minHeight + CGFloat(level) * (maxHeight - minHeight)
                    )
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels.map { Int($0 * 100) })
    }
}
