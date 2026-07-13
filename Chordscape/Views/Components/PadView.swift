import SwiftUI

/// One of the 7 diatonic pads. Purely presentational — `isActive` drives the
/// pressed look, and touch handling lives one level up in `ContentView`
/// (the whole row shares one gesture per pad-origin so a drag can glide
/// across neighboring pads instead of each pad owning an isolated gesture).
struct PadView: View {
    let label: String
    let color: Color
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(color.opacity(isActive ? 1.0 : 0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0.65 : 0.25), lineWidth: 2)
            )
            .overlay(
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .scaleEffect(isActive ? 0.94 : 1.0)
            .shadow(color: color.opacity(isActive ? 0.1 : 0.35), radius: isActive ? 2 : 8, y: isActive ? 1 : 5)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isActive)
    }
}
