import CoreGraphics
import Foundation

/// Bridges the UI to `ChordscapeAudioEngine`. Owns the tonal/generative controls
/// (root, scale, complexity, key mode/quality, voicing, performance mode)
/// and forwards tone/loop knobs straight into the engine's thread-safe
/// setters. Chord generation + voicing math happens here (pure, testable,
/// no audio-thread concerns) — the engine only ever receives final notes.
@MainActor
final class ChordscapeViewModel: ObservableObject {
    static let degreeCount = 7
    private static let bassOctaveBase = 24 // ~2 octaves below the chord voices' octaveBase (48)

    let engine = ChordscapeAudioEngine()

    @Published var rootPitchClass: Int = 0 // C
    @Published var scale: MusicalScale = .major
    @Published var complexity: Float = 0.4
    @Published var voicingSteps: Float = 0 // -6...6, chord inversion (see ChordEngine.applyVoicing)

    /// Orchid's "Key Mode": on (default) auto-picks each pad's quality from
    /// the scale, like Chordscape always did before this was added. Off hands
    /// quality to `chordQuality` instead, so any pad's root can carry any
    /// quality regardless of what the scale would diatonically put there.
    @Published var keyModeOn: Bool = true
    @Published var chordQuality: ChordQualityOverride = .major

    @Published var performanceMode: PerformanceMode = .sustain

    /// Every engine in here sounds together, layered — one chord press
    /// triggers a full polyphonic voice group per active engine (e.g. Sub +
    /// FM + Reed all on means every note plays through all three at once).
    /// Never allowed to go empty; `toggleEngine(_:)` is the only mutator UI
    /// should use, since it enforces that. `engine.setActiveEngines(...)` is
    /// pushed on every change purely so the loop clock (audio-thread side)
    /// knows what to play recorded steps back through — pad presses instead
    /// pass this set explicitly per command, not via that cross-thread copy.
    @Published var activeEngines: Set<SynthEngineType> = [.subtractive] {
        didSet { engine.setActiveEngines(activeEngines) }
    }
    @Published var tone: Float = 2_400 {
        didSet { engine.setCutoff(tone) }
    }
    @Published var decayKnob: Float = 0.35 {
        didSet { engine.setDecay(decayKnob) }
    }
    @Published var ambience: Float = 0.3 {
        didSet { engine.setAmbience(ambience) }
    }
    @Published var tempo: Float = 100 {
        didSet { engine.setTempo(tempo) }
    }
    @Published var bassLevel: Float = 0.5 {
        didSet { engine.setBassLevel(bassLevel) }
    }
    /// Glissando duration in seconds — 0 would still work (the engine floors
    /// it to 1ms) but stays audibly instant, which is fine: it only ever
    /// applies to the drag-across-pads gesture, never a plain tap.
    @Published var glideTime: Float = 0.15

    /// Which knob the drag-up filter-mod gesture sweeps — Filter (cutoff)
    /// by default, matching the original design; see `padModulationChanged`.
    @Published var modulationTarget: ModulationTarget = .filter

    /// Toggles `engine` on/off in `activeEngines` — refuses to remove the
    /// last remaining one, since an empty engine set would mean every pad
    /// press produces silence.
    func toggleEngine(_ engine: SynthEngineType) {
        if activeEngines.contains(engine) {
            guard activeEngines.count > 1 else { return }
            activeEngines.remove(engine)
        } else {
            activeEngines.insert(engine)
        }
    }

    @Published var currentPatchName: String = "Init"
    @Published var userPatches: [Patch] = []

    @Published var activePads: Set<Int> = []

    /// Which pads are currently held, main-thread only — decides when the
    /// monophonic bass note should actually let go (only once every pad is
    /// up), independent of the polyphonic chord voices above it.
    private var heldPadRoots: [Int: Int] = [:]
    /// Which pad is currently driving the bass note (the first pad of a
    /// hold-group). Tracked explicitly so a glissando on some OTHER pad
    /// (while this one is independently still held, e.g. a second finger)
    /// can't steal/retarget the bass out from under it — that was a real
    /// bug: `performGlide` used to send a bass retarget unconditionally on
    /// every glide step, so gliding pad B while pad A was separately held
    /// would leave the bass parked on B's last pitch even after B released,
    /// since `heldPadRoots` wasn't empty (A was still down) and so
    /// `releaseBass` never fired — an audible stuck note.
    private var bassOwnerPad: Int?

    /// External MIDI note -> which pad it got snapped to, so `externalNoteOff`
    /// releases the same pad even if root/scale changed mid-hold.
    private var midiNoteToPad: [Int: Int] = [:]
    /// How many currently-held MIDI notes are snapped to each pad — two
    /// colliding notes (e.g. both nearest to the same pad) must not let a
    /// release of one silence a pad the other is still holding.
    private var midiPadHoldCounts: [Int: Int] = [:]

    func start() {
        engine.start()
        engine.setActiveEngines(activeEngines)
        engine.setCutoff(tone)
        engine.setDecay(decayKnob)
        engine.setAmbience(ambience)
        engine.setTempo(tempo)
        engine.setBassLevel(bassLevel)
        userPatches = PatchStore.loadAll()
    }

    // MARK: - Patches

    /// Applies every tone/generative setting from `patch` — each is a
    /// normal `@Published` assignment, so the ones with `didSet` (engine
    /// type, tone, decay, ambience, tempo, bass level) push to the engine
    /// exactly like a knob drag would; the rest just take effect on the
    /// next pad press.
    func loadPatch(_ patch: Patch) {
        currentPatchName = patch.name
        rootPitchClass = patch.rootPitchClass
        scale = patch.scale
        complexity = patch.complexity
        voicingSteps = patch.voicingSteps
        keyModeOn = patch.keyModeOn
        chordQuality = patch.chordQuality
        performanceMode = patch.performanceMode
        activeEngines = patch.activeEngines.isEmpty ? [.subtractive] : patch.activeEngines
        tone = patch.tone
        decayKnob = patch.decayKnob
        ambience = patch.ambience
        bassLevel = patch.bassLevel
        glideTime = patch.glideTime
        tempo = patch.tempo
        modulationTarget = patch.modulationTarget
    }

    func saveCurrentPatch(as name: String) {
        let patch = Patch(
            name: name, rootPitchClass: rootPitchClass, scale: scale, complexity: complexity,
            voicingSteps: voicingSteps, keyModeOn: keyModeOn, chordQuality: chordQuality,
            performanceMode: performanceMode, activeEngines: activeEngines, tone: tone, decayKnob: decayKnob,
            ambience: ambience, bassLevel: bassLevel, glideTime: glideTime, tempo: tempo,
            modulationTarget: modulationTarget
        )
        PatchStore.save(patch)
        userPatches.append(patch)
        userPatches.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        currentPatchName = name
    }

    func deletePatch(_ patch: Patch) {
        PatchStore.delete(patch)
        userPatches.removeAll { $0.id == patch.id }
    }

    func padDown(_ padID: Int) {
        let rawChord = keyModeOn
            ? ChordEngine.generate(rootPitchClass: rootPitchClass, scale: scale, degreeIndex: padID, complexity: complexity)
            : ChordEngine.generateChromatic(rootPitchClass: padRootPitchClass(padID), quality: chordQuality, complexity: complexity)

        let voicedNotes = ChordEngine.applyVoicing(rawChord.midiNotes, steps: Int(voicingSteps.rounded()))
        let label = ChordEngine.slashLabel(rawChord.label, voicedNotes: voicedNotes, rootPitchClass: rawChord.rootPitchClass)
        let chord = GeneratedChord(midiNotes: voicedNotes, label: label, rootPitchClass: rawChord.rootPitchClass)

        activePads.insert(padID)
        let isFirstHeldPad = heldPadRoots.isEmpty
        heldPadRoots[padID] = rawChord.rootPitchClass

        engine.padDown(padID: padID, chord: chord, mode: performanceMode, engines: activeEngines)

        if isFirstHeldPad {
            bassOwnerPad = padID
            engine.triggerBass(midi: Self.bassOctaveBase + rawChord.rootPitchClass)
        }
    }

    func padUp(_ padID: Int) {
        activePads.remove(padID)
        heldPadRoots.removeValue(forKey: padID)
        engine.padUp(padID: padID)
        if heldPadRoots.isEmpty {
            bassOwnerPad = nil
            engine.releaseBass()
        }
    }

    /// The root pitch class a given pad plays — reused by both the diatonic
    /// path (as a scale degree) and the Key-Mode-off chromatic path (as a
    /// convenient 7-note root palette). Known simplification: Key Mode off
    /// still only offers these 7 roots, not full 12-tone chromatic freedom —
    /// see PROGRESS.md.
    func padRootPitchClass(_ padID: Int) -> Int {
        let intervals = scale.intervals
        return (rootPitchClass + intervals[padID % intervals.count]) % 12
    }

    func degreeName(_ index: Int) -> String {
        ChordEngine.pitchClassNames[padRootPitchClass(index)]
    }

    // MARK: - External MIDI controller

    /// A connected MIDI controller doesn't have 7 pads — any of the 12
    /// chromatic keys can come in. Each incoming note snaps to whichever pad
    /// currently sits closest in pitch class (ignoring octave, same as pads
    /// themselves always render at a fixed octave regardless of where on the
    /// pad row you tapped), then plays exactly like a tap: same chord
    /// generation, voicing, and performance mode.
    func externalNoteOn(_ midiNote: Int) {
        let pitchClass = ((midiNote % 12) + 12) % 12
        let pad = nearestPad(forPitchClass: pitchClass)
        midiNoteToPad[midiNote] = pad
        let holdCount = (midiPadHoldCounts[pad] ?? 0) + 1
        midiPadHoldCounts[pad] = holdCount
        if holdCount == 1 {
            padDown(pad)
        }
    }

    func externalNoteOff(_ midiNote: Int) {
        guard let pad = midiNoteToPad.removeValue(forKey: midiNote) else { return }
        let holdCount = max((midiPadHoldCounts[pad] ?? 1) - 1, 0)
        if holdCount == 0 {
            midiPadHoldCounts.removeValue(forKey: pad)
            padUp(pad)
        } else {
            midiPadHoldCounts[pad] = holdCount
        }
    }

    private func nearestPad(forPitchClass pitchClass: Int) -> Int {
        var bestPad = 0
        var bestDistance = Int.max
        for pad in 0..<Self.degreeCount {
            let diff = abs(padRootPitchClass(pad) - pitchClass)
            let circularDistance = min(diff, 12 - diff)
            if circularDistance < bestDistance {
                bestDistance = circularDistance
                bestPad = pad
            }
        }
        return bestPad
    }

    // MARK: - Glissando (drag across the pad row)

    /// Keyed by the pad each drag *started* on (SwiftUI keeps delivering a
    /// touch's updates to whichever view captured it, even once the finger
    /// has visually moved over a neighboring pad) — so two simultaneous
    /// drags from two different fingers each get their own independent
    /// entry instead of clobbering a single shared "current pad" variable.
    /// Known simplification: if two separate drags converge on the *same*
    /// target pad, releasing one of them will cut it even though the other
    /// is still "holding" it — an accepted edge case, see PROGRESS.md.
    private var glissandoCurrentPad: [Int: Int] = [:]

    /// Called on every touch update for the drag that started on `originPad`.
    /// `translationX` is that drag's horizontal offset from where it began;
    /// dividing by `padWidth` turns it into "how many pads over" and snaps
    /// to the nearest one. The very first call (translation ≈ 0) behaves
    /// exactly like a plain tap-down on `originPad`. `translationY` drives
    /// the filter-mod gesture (see `padModulationChanged`) — independent of
    /// the X-axis glissando, so a diagonal drag does both at once.
    func glissandoChanged(originPad: Int, translationX: CGFloat, translationY: CGFloat, padWidth: CGFloat) {
        padModulationChanged(translationY: translationY)

        guard padWidth > 0 else { return }
        let offset = Int((translationX / padWidth).rounded())
        let targetPad = min(max(originPad + offset, 0), Self.degreeCount - 1)

        guard let current = glissandoCurrentPad[originPad] else {
            glissandoCurrentPad[originPad] = targetPad
            padDown(targetPad)
            return
        }
        guard targetPad != current else { return }
        glissandoCurrentPad[originPad] = targetPad
        performGlide(from: current, to: targetPad)
    }

    func glissandoEnded(originPad: Int) {
        guard let current = glissandoCurrentPad.removeValue(forKey: originPad) else { return }
        padUp(current)
        padModulationEnded()
    }

    // MARK: - Filter mod (drag up from a held pad)

    /// Filter cutoff is a single value shared by every voice (see
    /// `VoiceParams`), not per-note — so this is necessarily a global "mod
    /// wheel" layered onto whichever touch is currently dragging, not true
    /// per-note expression. Known simplification: with two fingers
    /// modulating on different pads at once, whichever's `onChanged` fires
    /// last wins, and either one lifting resets the shared cutoff back to
    /// the Tone knob's value even if the other finger is still dragging —
    /// an accepted edge case for a feature that's clearly aimed at the
    /// single-finger case.
    private let modDragRange: CGFloat = 120 // px of upward drag for full brightness

    /// 0...1, how engaged the filter-mod gesture currently is — published
    /// purely so `ContentView` can drive the finger-following glow's
    /// size/brightness off it; nothing audio-related reads this.
    @Published var modulationAmount: Float = 0

    private func padModulationChanged(translationY: CGFloat) {
        let amount = Float((max(0, -translationY) / modDragRange)).clamped(0, 1)
        modulationAmount = amount
        switch modulationTarget {
        case .filter:
            let modulatedCutoff = (tone + amount * (6_000 - tone)).clamped(300, 6_000)
            engine.setCutoff(modulatedCutoff)
        case .ambience:
            let modulatedAmbience = (ambience + amount * (1 - ambience)).clamped(0, 1)
            engine.setAmbience(modulatedAmbience)
        case .decay:
            let modulatedDecay = (decayKnob + amount * (1 - decayKnob)).clamped(0, 1)
            engine.setDecay(modulatedDecay)
        case .bass:
            let modulatedBass = (bassLevel + amount * (1 - bassLevel)).clamped(0, 1)
            engine.setBassLevel(modulatedBass)
        }
    }

    private func padModulationEnded() {
        modulationAmount = 0
        switch modulationTarget {
        case .filter: engine.setCutoff(tone)
        case .ambience: engine.setAmbience(ambience)
        case .decay: engine.setDecay(decayKnob)
        case .bass: engine.setBassLevel(bassLevel)
        }
    }

    private func performGlide(from oldPad: Int, to newPad: Int) {
        let rawChord = keyModeOn
            ? ChordEngine.generate(rootPitchClass: rootPitchClass, scale: scale, degreeIndex: newPad, complexity: complexity)
            : ChordEngine.generateChromatic(rootPitchClass: padRootPitchClass(newPad), quality: chordQuality, complexity: complexity)

        let voicedNotes = ChordEngine.applyVoicing(rawChord.midiNotes, steps: Int(voicingSteps.rounded()))
        let label = ChordEngine.slashLabel(rawChord.label, voicedNotes: voicedNotes, rootPitchClass: rawChord.rootPitchClass)
        let chord = GeneratedChord(midiNotes: voicedNotes, label: label, rootPitchClass: rawChord.rootPitchClass)

        activePads.remove(oldPad)
        activePads.insert(newPad)
        heldPadRoots.removeValue(forKey: oldPad)
        heldPadRoots[newPad] = rawChord.rootPitchClass

        // Bass is a single always-mono voice with no concept of performance
        // mode at all — it glides on every crossing regardless of whether
        // the chord voices above it are gliding, retargeting, or resetting.
        // Only retarget it if THIS glide's pad is the one actually driving
        // it, though — otherwise an independently-held pad's bass note
        // would get silently hijacked by a completely unrelated glissando
        // elsewhere on the pad row (a real bug, fixed earlier this session).
        if bassOwnerPad == oldPad {
            bassOwnerPad = newPad
            engine.glideBass(to: Self.bassOctaveBase + rawChord.rootPitchClass, glideSeconds: glideTime)
        }

        switch performanceMode {
        case .sustain:
            // The old pad's notes are just sitting there ringing — a true
            // pitch glide reads naturally.
            engine.glideChordVoices(fromPadID: oldPad, toPadID: newPad, chord: chord, engines: activeEngines, glideSeconds: glideTime)
        case .arp:
            // An arpeggiator has no clean "portamento" concept — it's
            // re-triggering the whole time. Retargeting (swap the note pool,
            // leave its clock alone) instead of gliding means notes keep
            // firing on the arp's own steady rhythm, playing whatever chord
            // is currently under the finger at each tick, rather than
            // snapping/restarting the instant a drag crosses a pad boundary.
            engine.retargetArp(fromPadID: oldPad, toPadID: newPad, chord: chord)
        case .strum, .slop:
            // Neither has a coherent "glide" or "retarget" reading (a strum
            // is a one-shot staggered onset, not a standing set of voices) —
            // a pad-crossing does a clean release-then-fresh-trigger.
            engine.padUp(padID: oldPad)
            engine.padDown(padID: newPad, chord: chord, mode: performanceMode, engines: activeEngines)
        }
    }

    // MARK: - Panic

    /// Recovery escape hatch for a stuck/hung note: immediately silences
    /// everything sounding and resets every piece of local "what's
    /// currently held" bookkeeping, so a subsequent tap starts from a clean
    /// slate no matter what state a bug left things in.
    func panicStopAll() {
        activePads.removeAll()
        heldPadRoots.removeAll()
        bassOwnerPad = nil
        glissandoCurrentPad.removeAll()
        midiNoteToPad.removeAll()
        midiPadHoldCounts.removeAll()
        engine.panicStopAll()
    }
}
