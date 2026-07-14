import SwiftUI

/// Self-contained rotary knob (no dependency on Modula's `ParameterDescriptor`
/// — Chordwright's controls are simple enough for a plain range). Vertical drag
/// changes value; double-tap resets to `defaultValue`.
struct ChordwrightKnob: View {
    let label: String
    let value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let valueText: (Float) -> String
    let onChange: (Float) -> Void

    @State private var dragStartValue: Float?
    @GestureState private var isDragging = false

    private let diameter: CGFloat = 50
    private let dragSensitivity: CGFloat = 130

    private var normalized: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var angle: Angle { .degrees(Double(normalized) * 270 - 135) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.chordwrightPanel)
                    .overlay(Circle().stroke(Color.chordwrightInk.opacity(0.12), lineWidth: 1))
                Circle()
                    .trim(from: 0, to: CGFloat(normalized))
                    .rotation(.degrees(-135))
                    .stroke(Color.chordwrightCoral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(5)
                Rectangle()
                    .fill(Color.chordwrightInk)
                    .frame(width: 3, height: diameter * 0.32)
                    .offset(y: -diameter * 0.18)
                    .rotationEffect(angle)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isDragging ? 1.07 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { drag in
                        if dragStartValue == nil { dragStartValue = value }
                        let delta = Float(-drag.translation.height / dragSensitivity) * (range.upperBound - range.lowerBound)
                        let newValue = (dragStartValue! + delta).clamped(range.lowerBound, range.upperBound)
                        onChange(newValue)
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
            .onTapGesture(count: 2) { onChange(defaultValue) }

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.chordwrightInk.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: diameter + 16)
            Text(valueText(value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.chordwrightInk.opacity(0.45))
        }
    }
}
