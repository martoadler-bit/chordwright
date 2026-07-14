import SwiftUI

/// A soft radial glow that follows a finger while it's down on a pad —
/// purely decorative, but its size/brightness track the filter-mod gesture
/// (dragging up) so it doubles as visual feedback for an otherwise
/// invisible audio effect: a glow that swells as the sound brightens.
struct GlowView: View {
    let color: Color
    let intensity: Float // 0...1, from ChordwrightViewModel.modulationAmount

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.9), color.opacity(0)],
                    center: .center, startRadius: 0, endRadius: 90
                )
            )
            .frame(width: 180, height: 180)
            .scaleEffect(0.55 + CGFloat(intensity) * 0.65)
            .opacity(0.35 + Double(intensity) * 0.55)
            .blur(radius: 4)
            .allowsHitTesting(false)
    }
}
