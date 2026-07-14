import AVFoundation
import Darwin

/// Owns the single `AVAudioEngine`, the poly synth, the dedicated bass
/// voice, the effects chain, and the 16-step loop clock — all in one place
/// since Chordwright's signal path is fixed (no patch graph to coordinate, unlike
/// Modula).
///
/// Threading discipline: `PolySynth`/`SynthVoice` are touched ONLY from the
/// audio render thread. UI actions (pad taps, transport) never call
/// `synth.trigger`/`release` directly — they enqueue a `SynthCommand` under
/// `commandLock`, and the render callback drains that queue before each
/// block. This mirrors Modula's rule that the render thread never shares
/// live mutable state with the main thread except through a lock-guarded
/// snapshot/queue. Performance-mode scheduling (strum/slop stagger, arp
/// stepping) follows the same rule: once a `.strum`/`.slop`/`.arpStart`
/// command is drained, all further timing state it creates
/// (`scheduledNotes`, `activeArps`) lives and is only ever touched on the
/// audio thread.
final class ChordwrightAudioEngine: ObservableObject {
    static let stepCount = 16

    @Published var currentChordLabel: String = "–"
    @Published var currentStep: Int = 0
    @Published var stepHasContent: [Bool] = Array(repeating: false, count: ChordwrightAudioEngine.stepCount)
    @Published var isLoopPlaying = false
    @Published var isRecording = false

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private let sampleRate: Double = 44_100

    private let synth = PolySynth()
    private let bassVoice = SynthVoice()
    private let delay = SimpleDelay()
    private let reverb = SimpleReverb()
    private let chorus = SimpleChorus()

    // MARK: Cross-thread control state (main thread writes, audio thread reads)

    private var controlLock = os_unfair_lock()
    private var _cutoff: Float = 2_400
    private var _decay: Float = 0.35
    private var _ambience: Float = 0.3
    private var _tempo: Float = 100
    private var _bassLevel: Float = 0.5
    private var _isLoopPlayingAudioThread = false
    /// Read by the loop clock, which always plays back through whatever
    /// engines are *currently* active — same philosophy as it always using
    /// plain sustained triggering regardless of the mode live at record
    /// time: the loop replays notes, not a frozen snapshot of every knob.
    private var _activeEngines: Set<SynthEngineType> = [.subtractive]

    private var loopLock = os_unfair_lock()
    private var loopSteps: [[Int]?] = Array(repeating: nil, count: ChordwrightAudioEngine.stepCount)

    private struct SynthCommand {
        enum Kind {
            case trigger(midiNotes: [Int], engines: Set<SynthEngineType>)   // all notes together, replacing whatever the group held
            case strum(midiNotes: [Int], engines: Set<SynthEngineType>)     // notes fire staggered low->high, then ring together
            case slop(midiNotes: [Int], engines: Set<SynthEngineType>)      // notes fire with small random jitter, then ring together
            case arpStart(midiNotes: [Int], engines: Set<SynthEngineType>)  // repeatedly cycles one note at a time until released
            case release
            case glideRetag(toGroupID: Int, midiNotes: [Int], engines: Set<SynthEngineType>, glideSeconds: Float) // chord (Sustain): slide existing voices to new notes, re-tag to toGroupID
            case arpRetarget(toGroupID: Int, midiNotes: [Int])                     // chord (Arp): swap note pool without resetting the arp's own timing or its engine set
            case glideNote(midi: Int, glideSeconds: Float)                          // bass: slide the single bass voice to a new note
            case panicStopAll // ignores groupID — instantly silences everything
        }
        let groupID: Int
        let kind: Kind
    }
    private var commandLock = os_unfair_lock()
    private var pendingCommands: [SynthCommand] = []

    // MARK: Audio-thread-only state (never touched from the main thread)

    private var stepSampleCounter = 0
    private var stepIndexAudioThread = -1
    private var activeStepGroupID: Int?
    private var wasLoopPlayingAudioThread = false

    private var audioSampleClock: Int64 = 0

    private struct ScheduledNote { let groupID: Int; let midi: Int; let engines: Set<SynthEngineType>; let fireAtSample: Int64 }
    private var scheduledNotes: [ScheduledNote] = []

    private struct ArpState { var notes: [Int]; let engines: Set<SynthEngineType>; var index: Int; var nextFireSample: Int64 }
    private var activeArps: [Int: ArpState] = [:]

    init() {
        delay.prepare(sampleRate: Float(sampleRate))
        reverb.prepare(sampleRate: Float(sampleRate))
        chorus.prepare(sampleRate: Float(sampleRate))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            fatalError("Failed to create audio format")
        }

        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCountValue, audioBufferList in
            guard let self else { return noErr }
            let frameCount = Int(frameCountValue)

            os_unfair_lock_lock(&self.controlLock)
            let cutoff = self._cutoff
            let decayVal = self._decay
            let ambience = self._ambience
            let tempo = self._tempo
            let bassLevel = self._bassLevel
            let loopPlaying = self._isLoopPlayingAudioThread
            let loopEngines = self._activeEngines
            os_unfair_lock_unlock(&self.controlLock)

            os_unfair_lock_lock(&self.commandLock)
            let commands = self.pendingCommands
            self.pendingCommands.removeAll(keepingCapacity: true)
            os_unfair_lock_unlock(&self.commandLock)
            for command in commands {
                self.apply(command)
            }

            self.synth.params = VoiceParams(cutoff: cutoff, decay: decayVal)
            self.delay.mix = ambience * 0.35
            self.reverb.mix = ambience * 0.45
            self.chorus.mix = 0.5 + ambience * 0.3

            self.fireScheduledNotes()
            self.advanceArps(tempo: tempo)

            if self.wasLoopPlayingAudioThread && !loopPlaying {
                if let prev = self.activeStepGroupID {
                    self.synth.release(groupID: prev)
                    self.activeStepGroupID = nil
                }
                self.stepSampleCounter = 0
                self.stepIndexAudioThread = -1
            }
            self.wasLoopPlayingAudioThread = loopPlaying

            if loopPlaying {
                self.stepSampleCounter += frameCount
                let samplesPerStep = Int(self.sampleRate * 60.0 / Double(max(tempo, 1)) / 4.0)
                if self.stepSampleCounter >= samplesPerStep {
                    self.stepSampleCounter -= samplesPerStep
                    self.advanceStep(engines: loopEngines)
                }
            }

            self.audioSampleClock += Int64(frameCount)

            var mono = self.synth.render(frameCount: frameCount, sampleRate: Float(self.sampleRate))
            for i in 0..<frameCount {
                mono[i] += self.bassVoice.render(params: self.bassParams, sampleRate: Float(self.sampleRate)) * bassLevel
            }

            var leftOut = [Float](repeating: 0, count: frameCount)
            var rightOut = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                let delayed = self.delay.process(mono[i], sampleRate: Float(self.sampleRate))
                let reverbed = self.reverb.process(delayed)
                let (l, r) = self.chorus.process(reverbed)
                leftOut[i] = l.clamped(-1, 1)
                rightOut[i] = r.clamped(-1, 1)
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for (index, buffer) in bufferList.enumerated() {
                guard let mData = buffer.mData else { continue }
                let samples = mData.assumingMemoryBound(to: Float.self)
                let source = index == 0 ? leftOut : rightOut
                for frame in 0..<frameCount { samples[frame] = source[frame] }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    /// Fixed, simple round tone for the bass — deliberately not switchable
    /// by the main Engine picker (Orchid's bass runs its own independent
    /// synth engine too). `bassVoice.currentEngine` is pinned to
    /// `.subtractive` at `noteOn`/`glideTo` time in `applyBass`, not read
    /// from these params — `VoiceParams` no longer carries an engine at all.
    private var bassParams: VoiceParams { VoiceParams(cutoff: 900, decay: 0.3) }

    func start() {
        guard !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            engine.prepare()
            try engine.start()
        } catch {
            print("Chordwright audio engine failed to start: \(error)")
        }
    }

    // MARK: - Tone controls

    func setCutoff(_ hz: Float) {
        os_unfair_lock_lock(&controlLock); _cutoff = hz; os_unfair_lock_unlock(&controlLock)
    }
    func setDecay(_ value: Float) {
        os_unfair_lock_lock(&controlLock); _decay = value; os_unfair_lock_unlock(&controlLock)
    }
    func setAmbience(_ value: Float) {
        os_unfair_lock_lock(&controlLock); _ambience = value; os_unfair_lock_unlock(&controlLock)
    }
    func setTempo(_ bpm: Float) {
        os_unfair_lock_lock(&controlLock); _tempo = bpm; os_unfair_lock_unlock(&controlLock)
    }
    func setBassLevel(_ value: Float) {
        os_unfair_lock_lock(&controlLock); _bassLevel = value; os_unfair_lock_unlock(&controlLock)
    }
    func setActiveEngines(_ engines: Set<SynthEngineType>) {
        os_unfair_lock_lock(&controlLock); _activeEngines = engines; os_unfair_lock_unlock(&controlLock)
    }

    /// Immediately silences every currently-sounding voice (chord pool +
    /// bass) and clears all pending strum/slop/arp state. A recovery escape
    /// hatch for a note that's somehow gotten stuck — doesn't stop the loop
    /// transport itself, just whatever's ringing right now.
    func panicStopAll() {
        enqueue(SynthCommand(groupID: 0, kind: .panicStopAll))
    }

    // MARK: - Live pads (chord voices only — bass is entirely separate, see below)

    /// `engines` is every currently-active engine — one chord press sounds
    /// through all of them layered (a full polyphonic voice group per
    /// engine), not a single shared timbre. Caller (`ChordwrightViewModel`)
    /// guarantees this is never empty.
    func padDown(padID: Int, chord: GeneratedChord, mode: PerformanceMode, engines: Set<SynthEngineType>) {
        let kind: SynthCommand.Kind
        switch mode {
        case .sustain: kind = .trigger(midiNotes: chord.midiNotes, engines: engines)
        case .strum: kind = .strum(midiNotes: chord.midiNotes, engines: engines)
        case .slop: kind = .slop(midiNotes: chord.midiNotes, engines: engines)
        case .arp: kind = .arpStart(midiNotes: chord.midiNotes, engines: engines)
        }
        enqueue(SynthCommand(groupID: padID, kind: kind))
        updateDisplay(chord)
    }

    func padUp(padID: Int) {
        enqueue(SynthCommand(groupID: padID, kind: .release))
    }

    /// Glissando in Sustain mode: slides whatever `fromPadID` is currently
    /// holding toward `chord`'s notes instead of releasing and
    /// re-triggering. Used when a drag crosses from one pad into another
    /// without lifting.
    func glideChordVoices(fromPadID: Int, toPadID: Int, chord: GeneratedChord, engines: Set<SynthEngineType>, glideSeconds: Float) {
        enqueue(SynthCommand(groupID: fromPadID, kind: .glideRetag(toGroupID: toPadID, midiNotes: chord.midiNotes, engines: engines, glideSeconds: glideSeconds)))
        updateDisplay(chord)
    }

    /// Glissando in Arp mode: an arpeggiator has no clean "portamento"
    /// concept (it's re-triggering the whole time), so instead of pitch-
    /// sliding, a pad-crossing just swaps which notes the in-flight arp
    /// draws from — its own ticking rhythm (`index`/`nextFireSample`) *and*
    /// its engine set are left completely undisturbed, so notes keep firing
    /// on the arp's own clock (through whichever engines it started with)
    /// rather than snapping the instant a drag crosses a pad boundary.
    func retargetArp(fromPadID: Int, toPadID: Int, chord: GeneratedChord) {
        enqueue(SynthCommand(groupID: fromPadID, kind: .arpRetarget(toGroupID: toPadID, midiNotes: chord.midiNotes)))
        updateDisplay(chord)
    }

    private func updateDisplay(_ chord: GeneratedChord) {
        currentChordLabel = chord.label
        if isRecording {
            setLoopStep(currentStep, midiNotes: chord.midiNotes)
        }
    }

    // MARK: - Bass (a single always-mono voice, fully independent of pad
    // performance mode — it always plain-triggers/releases/glides the same
    // way no matter what the chord voices above it are doing)

    func triggerBass(midi: Int) {
        enqueue(SynthCommand(groupID: Self.bassGroupIDConstant, kind: .trigger(midiNotes: [midi], engines: [.subtractive])))
    }

    func releaseBass() {
        enqueue(SynthCommand(groupID: Self.bassGroupIDConstant, kind: .release))
    }

    func glideBass(to midi: Int, glideSeconds: Float) {
        enqueue(SynthCommand(groupID: Self.bassGroupIDConstant, kind: .glideNote(midi: midi, glideSeconds: glideSeconds)))
    }

    private static let bassGroupIDConstant = -1

    private func enqueue(_ command: SynthCommand) {
        os_unfair_lock_lock(&commandLock)
        pendingCommands.append(command)
        os_unfair_lock_unlock(&commandLock)
    }

    /// Audio-thread only — interprets one drained `SynthCommand`. The bass
    /// groupID is routed to the dedicated `bassVoice` directly rather than
    /// the shared `synth` pool — it's a single always-mono voice with its
    /// own fixed tone, not part of the chord pool's voice-stealing/tagging.
    private func apply(_ command: SynthCommand) {
        if case .panicStopAll = command.kind {
            synth.hardStopAll()
            bassVoice.hardStop()
            scheduledNotes.removeAll()
            activeArps.removeAll()
            activeStepGroupID = nil
            return
        }
        if command.groupID == Self.bassGroupIDConstant {
            applyBass(command)
            return
        }
        switch command.kind {
        case .trigger(let notes, let engines):
            synth.trigger(midiNotes: notes, groupID: command.groupID, engines: engines)
        case .strum(let notes, let engines):
            let strideSamples = Int64(0.02 * sampleRate) // ~20ms between onsets
            for (i, midi) in notes.enumerated() {
                scheduledNotes.append(ScheduledNote(groupID: command.groupID, midi: midi, engines: engines, fireAtSample: audioSampleClock + Int64(i) * strideSamples))
            }
        case .slop(let notes, let engines):
            let maxJitterSamples = Int64(0.035 * sampleRate) // up to ~35ms, unordered
            for midi in notes {
                let jitter = maxJitterSamples > 0 ? Int64.random(in: 0...maxJitterSamples) : 0
                scheduledNotes.append(ScheduledNote(groupID: command.groupID, midi: midi, engines: engines, fireAtSample: audioSampleClock + jitter))
            }
        case .arpStart(let notes, let engines):
            guard !notes.isEmpty else { return }
            activeArps[command.groupID] = ArpState(notes: notes, engines: engines, index: 0, nextFireSample: audioSampleClock)
        case .release:
            synth.release(groupID: command.groupID)
            scheduledNotes.removeAll { $0.groupID == command.groupID }
            activeArps.removeValue(forKey: command.groupID)
        case .glideRetag(let toGroupID, let notes, let engines, let glideSeconds):
            synth.glideChord(fromGroupID: command.groupID, toGroupID: toGroupID, midiNotes: notes, engines: engines, glideSeconds: glideSeconds, sampleRate: Float(sampleRate))
        case .arpRetarget(let toGroupID, let notes):
            guard var state = activeArps.removeValue(forKey: command.groupID) else {
                // No arp was actually running under the old tag (edge case,
                // e.g. it already finished/got released) — drop the
                // crossing silently rather than guessing an engine set.
                return
            }
            // The currently-sounding voice is still tagged with the OLD
            // groupID — retag it (not release+retrigger) so it keeps
            // ringing undisturbed and stays findable by a later
            // release/retarget under the new tag.
            if command.groupID != toGroupID {
                synth.retagGroup(from: command.groupID, to: toGroupID)
            }
            state.notes = notes // next tick (and beyond) draws from the new chord; index/nextFireSample untouched
            activeArps[toGroupID] = state
        case .glideNote:
            break // chord voices only; bass glide is handled in applyBass
        case .panicStopAll:
            break // handled above before this switch is ever reached
        }
    }

    /// Audio-thread only — the bass's own tiny command interpreter. Not part
    /// of the `synth` pool, so it never needs group tagging beyond "is this
    /// the bass": `.trigger`/`.release` are always a single note.
    private func applyBass(_ command: SynthCommand) {
        switch command.kind {
        case .trigger(let notes, _):
            if let midi = notes.first {
                bassVoice.noteOn(midi: midi, groupID: Self.bassGroupIDConstant, engine: .subtractive)
            }
        case .release:
            bassVoice.noteOff()
        case .glideNote(let midi, let glideSeconds):
            if bassVoice.isIdle {
                bassVoice.noteOn(midi: midi, groupID: Self.bassGroupIDConstant, engine: .subtractive)
            } else {
                bassVoice.glideTo(midi: midi, groupID: Self.bassGroupIDConstant, glideSeconds: glideSeconds, sampleRate: Float(sampleRate))
            }
        case .strum, .slop, .arpStart, .glideRetag, .arpRetarget, .panicStopAll:
            break // bass is always plain-sustained/glided, never arpeggiated/strummed
        }
    }

    /// Audio-thread only — fires any strum/slop notes whose scheduled time
    /// has arrived. Block-quantized (checked once per callback, not per
    /// sample), same accepted jitter as the loop clock.
    private func fireScheduledNotes() {
        guard !scheduledNotes.isEmpty else { return }
        var stillPending: [ScheduledNote] = []
        stillPending.reserveCapacity(scheduledNotes.count)
        for note in scheduledNotes {
            if audioSampleClock >= note.fireAtSample {
                for engine in note.engines {
                    synth.addNote(note.midi, groupID: note.groupID, engine: engine)
                }
            } else {
                stillPending.append(note)
            }
        }
        scheduledNotes = stillPending
    }

    /// Audio-thread only — steps every active arpeggiator forward at an
    /// eighth-note rate derived from the current tempo. Each step's single
    /// note still sounds through every one of that arp's active engines
    /// layered — layering applies at the note level, same as every other
    /// performance mode.
    private func advanceArps(tempo: Float) {
        guard !activeArps.isEmpty else { return }
        let stepSamples = Int64(sampleRate * 60.0 / Double(max(tempo, 1)) / 2.0)
        guard stepSamples > 0 else { return }
        for (groupID, var state) in activeArps {
            var guardCount = 0
            while audioSampleClock >= state.nextFireSample && guardCount < 8 {
                synth.release(groupID: groupID)
                let midi = state.notes[state.index % state.notes.count]
                for engine in state.engines {
                    synth.addNote(midi, groupID: groupID, engine: engine)
                }
                state.index += 1
                state.nextFireSample += stepSamples
                guardCount += 1
            }
            activeArps[groupID] = state
        }
    }

    // MARK: - Loop

    func togglePlay() {
        isLoopPlaying.toggle()
        os_unfair_lock_lock(&controlLock); _isLoopPlayingAudioThread = isLoopPlaying; os_unfair_lock_unlock(&controlLock)
    }

    func toggleRecording() {
        isRecording.toggle()
        if isRecording && !isLoopPlaying { togglePlay() }
    }

    func setLoopStep(_ index: Int, midiNotes: [Int]?) {
        guard loopSteps.indices.contains(index) else { return }
        os_unfair_lock_lock(&loopLock); loopSteps[index] = midiNotes; os_unfair_lock_unlock(&loopLock)
        stepHasContent[index] = midiNotes != nil
    }

    func clearLoop() {
        os_unfair_lock_lock(&loopLock)
        loopSteps = Array(repeating: nil, count: Self.stepCount)
        os_unfair_lock_unlock(&loopLock)
        stepHasContent = Array(repeating: false, count: Self.stepCount)
    }

    /// Audio-thread only — advances the step clock, releases the previous
    /// step's notes, and triggers whatever the new step holds (if anything).
    /// Loop playback always uses plain sustained `trigger` semantics,
    /// independent of whatever performance mode was live when a step was
    /// recorded — the mode is a live-play gesture, not part of the loop data.
    private func advanceStep(engines: Set<SynthEngineType>) {
        let next = (stepIndexAudioThread + 1) % Self.stepCount
        stepIndexAudioThread = next

        if let prev = activeStepGroupID {
            synth.release(groupID: prev)
        }

        os_unfair_lock_lock(&loopLock)
        let notes = loopSteps[next]
        os_unfair_lock_unlock(&loopLock)

        if let notes, !notes.isEmpty {
            let gid = 1_000 + next
            synth.trigger(midiNotes: notes, groupID: gid, engines: engines)
            activeStepGroupID = gid
        } else {
            activeStepGroupID = nil
        }

        DispatchQueue.main.async { [weak self] in self?.currentStep = next }
    }
}
