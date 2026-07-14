import SwiftUI

/// Root pitch class + scale, each a compact pill with a menu — a 12-way
/// segmented control would be too cramped on iPhone width (same lesson as
/// BrassLab's root picker). Also carries the Key Mode toggle since it
/// governs how the scale/root above actually get used: on, pads derive
/// quality diatonically; off, quality comes from the quality picker instead.
struct RootScalePickerView: View {
    @Binding var rootPitchClass: Int
    @Binding var scale: MusicalScale
    @Binding var keyModeOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(0..<12, id: \.self) { pc in
                    Button(ChordEngine.pitchClassNames[pc]) { rootPitchClass = pc }
                }
            } label: {
                pill(ChordEngine.pitchClassNames[rootPitchClass])
            }
            Menu {
                ForEach(MusicalScale.allCases) { s in
                    Button(s.rawValue) { scale = s }
                }
            } label: {
                pill(scale.rawValue)
            }
            Spacer()
            Button {
                keyModeOn.toggle()
            } label: {
                Text("Key \(keyModeOn ? "On" : "Off")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(keyModeOn ? Color.chordwrightInk : Color.chordwrightPanel))
                    .foregroundStyle(keyModeOn ? Color.white : Color.chordwrightInk)
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.chordwrightPanel))
            .foregroundStyle(Color.chordwrightInk)
    }
}
