import Foundation

/// A snapshot of the instrument's tone/generative settings — everything
/// that shapes how pads sound and behave. Deliberately does NOT include the
/// loop's recorded content — that's session data (what you played), not
/// part of the instrument's "sound", the same distinction a hardware synth
/// draws between a patch and a song.
struct Patch: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String

    var rootPitchClass: Int
    var scale: MusicalScale
    var complexity: Float
    var voicingSteps: Float
    var keyModeOn: Bool
    var chordQuality: ChordQualityOverride
    var performanceMode: PerformanceMode

    /// Every engine in here sounds together, layered — one chord press
    /// triggers a full polyphonic voice group per active engine, not a
    /// single shared timbre. Must never be empty; the UI guards against
    /// deselecting the last one.
    var activeEngines: Set<SynthEngineType>
    var tone: Float
    var decayKnob: Float
    var ambience: Float
    var bassLevel: Float
    var glideTime: Float
    var tempo: Float

    /// Which knob the drag-up-from-a-pad gesture sweeps. Defaulted so older
    /// saved patches (from before this field existed) still decode fine —
    /// missing key just falls back to `.filter`.
    var modulationTarget: ModulationTarget = .filter
}

/// A starting library spanning moods/scales/performance-modes rather than
/// just one example per engine — several engines get 2+ genuinely different
/// patches (a pad vs. a stab, a chime vs. a drone) so browsing feels like a
/// real preset library, not a mechanical "here's what each oscillator
/// sounds like" tour. One patch (`Layered Stack`) shows off multiple active
/// engines at once.
enum FactoryPatches {
    static let all: [Patch] = [
        Patch(
            name: "Init", rootPitchClass: 0, scale: .major, complexity: 0.4, voicingSteps: 0,
            keyModeOn: true, chordQuality: .major, performanceMode: .sustain,
            activeEngines: [.subtractive], tone: 2_400, decayKnob: 0.35, ambience: 0.3, bassLevel: 0.5, glideTime: 0.15, tempo: 100
        ),
        Patch(
            name: "Warm Pad", rootPitchClass: 0, scale: .major, complexity: 0.6, voicingSteps: 0,
            keyModeOn: true, chordQuality: .major, performanceMode: .sustain,
            activeEngines: [.subtractive], tone: 1_400, decayKnob: 0.85, ambience: 0.7, bassLevel: 0.4, glideTime: 0.3, tempo: 90
        ),
        Patch(
            name: "Analog Stab", rootPitchClass: 4, scale: .dorian, complexity: 0.3, voicingSteps: 0,
            keyModeOn: true, chordQuality: .minor, performanceMode: .strum,
            activeEngines: [.subtractive], tone: 3_200, decayKnob: 0.1, ambience: 0.2, bassLevel: 0.6, glideTime: 0.05, tempo: 118
        ),
        Patch(
            name: "FM Dream", rootPitchClass: 2, scale: .mixolydian, complexity: 0.7, voicingSteps: -2,
            keyModeOn: true, chordQuality: .major, performanceMode: .slop,
            activeEngines: [.fm], tone: 2_400, decayKnob: 0.6, ambience: 0.6, bassLevel: 0.5, glideTime: 0.2, tempo: 95
        ),
        Patch(
            name: "FM Chimes", rootPitchClass: 9, scale: .dorian, complexity: 0.25, voicingSteps: 2,
            keyModeOn: true, chordQuality: .minor, performanceMode: .arp,
            activeEngines: [.fm], tone: 3_800, decayKnob: 0.45, ambience: 0.5, bassLevel: 0.35, glideTime: 0.1, tempo: 132
        ),
        Patch(
            name: "Glass Bell", rootPitchClass: 0, scale: .dorian, complexity: 0.3, voicingSteps: 1,
            keyModeOn: true, chordQuality: .major, performanceMode: .arp,
            activeEngines: [.bell], tone: 3_500, decayKnob: 0.55, ambience: 0.55, bassLevel: 0.3, glideTime: 0.1, tempo: 120
        ),
        Patch(
            name: "Music Box", rootPitchClass: 5, scale: .major, complexity: 0.2, voicingSteps: 3,
            keyModeOn: true, chordQuality: .major, performanceMode: .sustain,
            activeEngines: [.bell], tone: 2_600, decayKnob: 0.7, ambience: 0.65, bassLevel: 0.25, glideTime: 0.25, tempo: 84
        ),
        Patch(
            name: "Pluck Garden", rootPitchClass: 7, scale: .major, complexity: 0.5, voicingSteps: 0,
            keyModeOn: true, chordQuality: .major, performanceMode: .strum,
            activeEngines: [.pluck], tone: 2_400, decayKnob: 0.2, ambience: 0.35, bassLevel: 0.45, glideTime: 0.15, tempo: 110
        ),
        Patch(
            name: "Harp Cascade", rootPitchClass: 0, scale: .mixolydian, complexity: 0.75, voicingSteps: -1,
            keyModeOn: true, chordQuality: .major, performanceMode: .arp,
            activeEngines: [.pluck], tone: 2_400, decayKnob: 0.35, ambience: 0.5, bassLevel: 0.4, glideTime: 0.1, tempo: 105
        ),
        Patch(
            name: "Reed Chorale", rootPitchClass: 0, scale: .harmonicMinor, complexity: 0.5, voicingSteps: 0,
            keyModeOn: true, chordQuality: .minor, performanceMode: .sustain,
            activeEngines: [.reed], tone: 2_000, decayKnob: 0.5, ambience: 0.4, bassLevel: 0.5, glideTime: 0.15, tempo: 100
        ),
        Patch(
            name: "Reed Groove", rootPitchClass: 7, scale: .dorian, complexity: 0.4, voicingSteps: 0,
            keyModeOn: true, chordQuality: .minor, performanceMode: .slop,
            activeEngines: [.reed], tone: 2_600, decayKnob: 0.15, ambience: 0.3, bassLevel: 0.55, glideTime: 0.1, tempo: 104
        ),
        Patch(
            name: "Square Lead", rootPitchClass: 0, scale: .wholeTone, complexity: 0.35, voicingSteps: 0,
            keyModeOn: false, chordQuality: .sus, performanceMode: .arp,
            activeEngines: [.square], tone: 2_800, decayKnob: 0.25, ambience: 0.3, bassLevel: 0.6, glideTime: 0.1, tempo: 128
        ),
        Patch(
            name: "Square Bloop", rootPitchClass: 2, scale: .naturalMinor, complexity: 0.3, voicingSteps: 0,
            keyModeOn: true, chordQuality: .minor, performanceMode: .strum,
            activeEngines: [.square], tone: 1_800, decayKnob: 0.15, ambience: 0.25, bassLevel: 0.5, glideTime: 0.1, tempo: 112
        ),
        Patch(
            name: "Layered Stack", rootPitchClass: 0, scale: .major, complexity: 0.35, voicingSteps: 0,
            keyModeOn: true, chordQuality: .major, performanceMode: .sustain,
            activeEngines: [.subtractive, .fm, .reed], tone: 2_200, decayKnob: 0.5, ambience: 0.45, bassLevel: 0.5, glideTime: 0.15, tempo: 100,
            modulationTarget: .ambience
        ),
    ]
}
