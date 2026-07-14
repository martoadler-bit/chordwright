import SwiftUI

/// A plain-language glossary of every control on the main screen — opened
/// from a "?" button in the header. Same `ScrollView`+`VStack` recipe as
/// `PatchBrowserView` (not `Form`/`List`, which bring default gray/white
/// styling that clashes with the app's custom cream palette), and the same
/// section-label + row-card visual language, so it reads as part of the
/// same app rather than a bolted-on help screen.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry {
        let title: String
        let text: String
    }

    private let sections: [(String, [Entry])] = [
        ("Playing", [
            Entry(title: "Pads", text: "Tap a pad to play its chord. Drag into a neighboring pad while holding to glide between chords. Drag straight up from a held pad to sweep the Mod Target knob."),
            Entry(title: "Root / Scale", text: "Sets the key everything is generated in."),
            Entry(title: "Key On/Off", text: "On: each pad's chord quality is picked automatically from the scale. Off: every pad uses the Quality picker below instead."),
            Entry(title: "Quality", text: "Only shown when Key is Off — forces every pad's chord to Diminished, Minor, Major, or Sus regardless of scale."),
        ]),
        ("Sound", [
            Entry(title: "Engines", text: "Which timbres are sounding. More than one can be on at once — they layer together on every chord, not one-at-a-time."),
            Entry(title: "Performance Mode", text: "Sustain holds notes steady. Arp cycles through the chord's notes. Strum staggers the onset low-to-high. Slop staggers with random timing."),
            Entry(title: "Mod Target", text: "Which knob the drag-up-from-a-pad gesture sweeps while held: Filter, Ambience, Decay, or Bass."),
        ]),
        ("Knobs", [
            Entry(title: "Complexity", text: "How often extra chord extensions (7ths, 9ths, 11ths...) get added on top of the basic triad."),
            Entry(title: "Voicing", text: "Cycles the chord's inversion — which note ends up on the bottom."),
            Entry(title: "Tone", text: "Filter brightness."),
            Entry(title: "Decay", text: "How quickly a held note fades, from percussive to sustained."),
            Entry(title: "Ambience", text: "Reverb/delay send amount."),
            Entry(title: "Glide", text: "How long a pad-to-pad drag takes to slide in pitch."),
            Entry(title: "Bass", text: "Volume of the separate low bass note that follows whichever pad is held."),
            Entry(title: "Tempo", text: "Speed of the loop and the Arp/Strum/Slop performance modes."),
        ]),
        ("Transport", [
            Entry(title: "Play / Record / Clear", text: "Record a 16-step loop of whatever you play, play it back, or clear it."),
            Entry(title: "Patches", text: "Tap the patch name under the title to save the current sound or load another one."),
            Entry(title: "Stop icon", text: "Panic button — instantly silences everything if a note ever gets stuck."),
        ]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.0) { section, entries in
                        sectionLabel(section)
                        ForEach(entries, id: \.title) { entry in
                            entryRow(entry)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.chordwrightBackground.ignoresSafeArea())
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.chordwrightInk.opacity(0.5))
    }

    private func entryRow(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.chordwrightInk)
            Text(entry.text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.chordwrightInk.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.chordwrightPanel))
    }
}
