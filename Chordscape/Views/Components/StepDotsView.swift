import SwiftUI

/// The loop's "screen" — 16 dots, one per step. The playhead dot grows and
/// turns coral; filled (but not current) steps are dark, empty ones are a
/// faint outline-ish tint.
struct StepDotsView: View {
    let stepHasContent: [Bool]
    let currentStep: Int
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(stepHasContent.indices, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: i))
                    .frame(width: dotSize(for: i), height: dotSize(for: i))
            }
        }
        .animation(.easeOut(duration: 0.12), value: currentStep)
    }

    private func dotSize(for i: Int) -> CGFloat {
        (i == currentStep && isPlaying) ? 10 : 7
    }

    private func dotColor(for i: Int) -> Color {
        if i == currentStep && isPlaying { return .chordscapeCoral }
        return stepHasContent[i] ? Color.chordscapeInk.opacity(0.55) : Color.chordscapeInk.opacity(0.15)
    }
}
