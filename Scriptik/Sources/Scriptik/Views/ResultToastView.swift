import SwiftUI

struct ResultToastView: View {
    let text: String
    @State private var appear = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.65)))
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text("Copied to Clipboard")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text(text)
                    .font(.system(.subheadline))
                    .foregroundStyle(.white)
                    .lineLimit(4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 320, height: 130)
        .scaleEffect(appear ? 1 : 0.88, anchor: .bottom)
        .opacity(appear ? 1 : 0)
        .animation(.spring(duration: 0.35), value: appear)
        .onAppear { appear = true }
    }
}
