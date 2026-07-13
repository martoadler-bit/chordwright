import SwiftUI

/// Anything pickable as a small icon+label pill row — `SynthEngineType`,
/// `ChordQualityOverride`, and `PerformanceMode` all conform, so the same
/// picker UI (originally written just for the engine) covers all three.
protocol PickerOption: CaseIterable, Identifiable, Equatable {
    var label: String { get }
    var icon: String { get }
}

/// N-way picker: a row of equal-width pills, selected one filled solid.
/// Icon and label sit side by side on one line (rather than stacked) so the
/// whole row stays short — with the screen now hosting 4+ of these rows
/// (Quality/Engines/Performance/Mod Target), the old stacked-icon style
/// added up to real scroll-forcing height.
struct SegmentedIconPicker<T: PickerOption>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 6) {
            ForEach(T.allCases) { option in
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(option.label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(selection == option ? Color.chordscapeInk : Color.chordscapePanel)
                    )
                    .foregroundStyle(selection == option ? Color.white : Color.chordscapeInk)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
