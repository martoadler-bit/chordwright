import SwiftUI

/// Same pill-row visual as `SegmentedIconPicker`, but any number of options
/// can be filled at once instead of exactly one — used for `activeEngines`,
/// where several timbres layer together rather than replacing each other.
struct MultiSegmentedIconPicker<T: PickerOption & Hashable>: View where T.AllCases: RandomAccessCollection {
    let selection: Set<T>
    let toggle: (T) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(T.allCases) { option in
                let isOn = selection.contains(option)
                Button {
                    toggle(option)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(option.label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(isOn ? Color.chordscapeInk : Color.chordscapePanel)
                    )
                    .foregroundStyle(isOn ? Color.white : Color.chordscapeInk)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
