import Foundation

/// A handful of common diatonic scales/modes — enough tonal variety for a
/// chord "ideas machine" without needing a full modal-theory picker.
enum MusicalScale: String, CaseIterable, Identifiable, Codable {
    case major = "Major"
    case naturalMinor = "Minor"
    case dorian = "Dorian"
    case mixolydian = "Mixolydian"
    case harmonicMinor = "Harmonic Minor"
    case wholeTone = "Whole Tone"

    var id: String { rawValue }

    /// Ascending semitone offsets from the root, one entry per scale degree.
    var intervals: [Int] {
        switch self {
        case .major:          return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor:   return [0, 2, 3, 5, 7, 8, 10]
        case .dorian:         return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian:     return [0, 2, 4, 5, 7, 9, 10]
        case .harmonicMinor:  return [0, 2, 3, 5, 7, 8, 11]
        case .wholeTone:      return [0, 2, 4, 6, 8, 10]
        }
    }
}

/// A chord voiced as actual MIDI notes, plus a human-readable label for the
/// "screen". Regenerated fresh on every pad press — the same pad can return
/// a different chord each time depending on `complexity`, which is the whole
/// point of an "ideas machine" (surprise within a controlled tonal frame).
struct GeneratedChord: Equatable {
    var midiNotes: [Int]
    var label: String
    var rootPitchClass: Int
}

/// Manual chord quality for "Key Mode off" — picked explicitly instead of
/// being derived from the scale, so any pad's root can carry any quality
/// (e.g. a borrowed/non-diatonic chord), mirroring Orchid's Dim/Min/Maj/Sus
/// buttons. Each case's `stackedIntervals` is a hand-authored 1-3-5-7-9-11-13
/// tower (absolute semitones from the root, already spanning octaves where
/// needed) rather than derived from a scale degree.
enum ChordQualityOverride: String, CaseIterable, Identifiable, PickerOption, Codable {
    case diminished = "Dim", minor = "Min", major = "Maj", sus = "Sus"

    var id: String { rawValue }
    var label: String { rawValue }

    var stackedIntervals: [Int] {
        switch self {
        case .diminished: return [0, 3, 6, 9, 14, 17, 20]
        case .minor:      return [0, 3, 7, 10, 14, 17, 21]
        case .major:      return [0, 4, 7, 11, 14, 18, 21] // #11 baked in directly, see ChordEngine.generate's note
        case .sus:        return [0, 5, 7, 10, 14, 17, 21]
        }
    }

    /// Only a major 3rd creates the natural-11-clashes-with-the-3rd problem
    /// that `stackedIntervals` above already routes around with a #11.
    var hasMajorThird: Bool { self == .major }

    var icon: String {
        switch self {
        case .diminished: return "circle.grid.cross"
        case .minor: return "arrow.down.circle"
        case .major: return "arrow.up.circle"
        case .sus: return "arrow.left.and.right.circle"
        }
    }
}

enum ChordEngine {
    static let pitchClassNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    /// Builds a stacked-thirds chord starting on scale degree `degreeIndex`
    /// (0-based) of `scale` rooted at `rootPitchClass`, then probabilistically
    /// piles on 7th/9th/11th/13th extensions as `complexity` (0...1) rises.
    /// `octaveBase` is the MIDI note of the root's lowest usable octave.
    static func generate(
        rootPitchClass: Int,
        scale: MusicalScale,
        degreeIndex: Int,
        complexity: Float,
        octaveBase: Int = 48
    ) -> GeneratedChord {
        let intervals = scale.intervals
        let count = intervals.count
        let degree = ((degreeIndex % count) + count) % count

        // Stack every other scale step starting from `degree`: 1, 3, 5, 7, 9, 11, 13.
        var scaleSteps: [Int] = [degree]
        var current = degree
        for _ in 0..<6 {
            current = (current + 2) % count
            scaleSteps.append(current)
        }

        // Always keep the triad (1-3-5); roll the dice for each extension in
        // order so higher complexity strictly means "at least as rich".
        var toneCount = 3
        let extensionChances: [Float] = [0.35, 0.6, 0.8, 0.92] // 7th, 9th, 11th, 13th thresholds
        for chance in extensionChances {
            if complexity >= chance || Float.random(in: 0...1) < complexity * 0.6 {
                toneCount += 1
            } else {
                break
            }
        }
        toneCount = min(toneCount, scaleSteps.count)

        // A diatonic natural 11th sits a half-step above a major 3rd — the
        // classic "avoid note" clash real players route around by raising it
        // to a #11 (Lydian over major, Lydian dominant over dominant7).
        // Minor-3rd chords have no such clash, so their 11th stays natural.
        let thirdInterval = (intervals[scaleSteps[1]] - intervals[degree] + 12) % 12
        let hasMajorThird = thirdInterval == 4

        // Convert each stacked scale step to an absolute MIDI note, climbing
        // an octave whenever the step index wraps past the top of the scale.
        var notes: [Int] = []
        for (i, step) in scaleSteps.prefix(toneCount).enumerated() {
            let octaveOffset = (degree + i * 2) / count
            let pitchClass = (rootPitchClass + intervals[step]) % 12
            var midi = octaveBase + pitchClass + 12 * octaveOffset
            if i == 5 && hasMajorThird {
                midi += 1 // natural 11 -> #11
            }
            notes.append(midi)
        }
        notes.sort()

        let degreeRootPC = (rootPitchClass + intervals[degree]) % 12
        let elevenIsSharped = hasMajorThird && notes.count >= 6
        let label = chordLabel(rootPitchClass: degreeRootPC, notes: notes, elevenIsSharped: elevenIsSharped)
        return GeneratedChord(midiNotes: notes, label: label, rootPitchClass: degreeRootPC)
    }

    /// Rough quality guess from the interval content, just for the on-screen label.
    private static func chordLabel(rootPitchClass: Int, notes: [Int], elevenIsSharped: Bool) -> String {
        guard let lowest = notes.min() else { return "" }
        let pcs = Set(notes.map { (($0 - lowest) % 12 + 12) % 12 })
        var suffix = ""
        if pcs.contains(3) && !pcs.contains(4) {
            suffix = "m"
        }
        if pcs.contains(10) { suffix += "7" }
        else if pcs.contains(11) { suffix += "maj7" }
        if notes.count >= 5 { suffix += "9" }
        if notes.count >= 6 { suffix += elevenIsSharped ? "(♯11)" : "11" }
        if notes.count >= 7 { suffix += "13" }
        return pitchClassNames[rootPitchClass] + suffix
    }

    /// "Key Mode off" path — builds from an explicitly chosen quality instead
    /// of a scale degree, so the root is free to carry any quality regardless
    /// of what the current scale would diatonically put there.
    static func generateChromatic(
        rootPitchClass: Int,
        quality: ChordQualityOverride,
        complexity: Float,
        octaveBase: Int = 48
    ) -> GeneratedChord {
        let stack = quality.stackedIntervals

        var toneCount = 3
        let extensionChances: [Float] = [0.35, 0.6, 0.8, 0.92]
        for chance in extensionChances {
            if complexity >= chance || Float.random(in: 0...1) < complexity * 0.6 {
                toneCount += 1
            } else {
                break
            }
        }
        toneCount = min(toneCount, stack.count)

        let notes = stack.prefix(toneCount).map { octaveBase + rootPitchClass + $0 }
        let label = chromaticLabel(
            rootPitchClass: rootPitchClass, quality: quality, noteCount: notes.count,
            elevenIsSharped: quality.hasMajorThird && notes.count >= 6
        )
        return GeneratedChord(midiNotes: notes, label: label, rootPitchClass: rootPitchClass)
    }

    private static func chromaticLabel(rootPitchClass: Int, quality: ChordQualityOverride, noteCount: Int, elevenIsSharped: Bool) -> String {
        let root = pitchClassNames[rootPitchClass]
        if quality == .sus {
            var suffix = noteCount >= 4 ? "7sus4" : "sus4"
            if noteCount >= 5 { suffix += "(9)" }
            if noteCount >= 6 { suffix += elevenIsSharped ? "(♯11)" : "(11)" }
            if noteCount >= 7 { suffix += "(13)" }
            return root + suffix
        }
        let symbolSuffix: String
        let seventhSuffix: String
        switch quality {
        case .diminished: symbolSuffix = "dim"; seventhSuffix = "7"
        case .minor:      symbolSuffix = "m";   seventhSuffix = "7"
        case .major:      symbolSuffix = "";    seventhSuffix = "maj7"
        case .sus:        symbolSuffix = "";    seventhSuffix = "" // unreachable, handled above
        }
        var suffix = symbolSuffix
        if noteCount >= 4 { suffix += seventhSuffix }
        if noteCount >= 5 { suffix += "9" }
        if noteCount >= 6 { suffix += elevenIsSharped ? "(♯11)" : "11" }
        if noteCount >= 7 { suffix += "13" }
        return root + suffix
    }

    /// Cycles the chord through inversions: positive `steps` move the
    /// lowest-sounding note up an octave, one step at a time (root position
    /// -> 1st inversion -> 2nd inversion -> ...); negative `steps` move the
    /// highest note down instead. Mirrors Orchid's single "Voicing" dial
    /// that "inverts chords in either direction."
    static func applyVoicing(_ notes: [Int], steps: Int) -> [Int] {
        guard !notes.isEmpty else { return notes }
        var result = notes
        var remaining = steps
        while remaining > 0 {
            if let minIndex = result.indices.min(by: { result[$0] < result[$1] }) {
                result[minIndex] += 12
            }
            remaining -= 1
        }
        while remaining < 0 {
            if let maxIndex = result.indices.min(by: { result[$0] > result[$1] }) {
                result[maxIndex] -= 12
            }
            remaining += 1
        }
        return result.sorted()
    }

    /// Appends "/bassNote" when voicing has put a note other than the root
    /// on the bottom — the standard slash-chord notation for an inversion.
    static func slashLabel(_ baseLabel: String, voicedNotes: [Int], rootPitchClass: Int) -> String {
        guard let lowest = voicedNotes.min() else { return baseLabel }
        let lowestPitchClass = ((lowest % 12) + 12) % 12
        guard lowestPitchClass != rootPitchClass else { return baseLabel }
        return baseLabel + "/" + pitchClassNames[lowestPitchClass]
    }
}
