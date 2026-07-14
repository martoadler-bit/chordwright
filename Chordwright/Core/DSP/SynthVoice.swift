import Foundation

enum SynthEngineType: Int, CaseIterable, Identifiable, PickerOption, Codable {
    case subtractive, fm, reed, square, bell, pluck

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .subtractive: return "Sub"
        case .fm: return "FM"
        case .reed: return "Reed"
        case .square: return "Square"
        case .bell: return "Bell"
        case .pluck: return "Pluck"
        }
    }

    var icon: String {
        switch self {
        case .subtractive: return "waveform"
        case .fm: return "waveform.path.ecg"
        case .reed: return "pianokeys"
        case .square: return "square.grid.2x2"
        case .bell: return "bell"
        case .pluck: return "guitars"
        }
    }
}

/// Tone knobs shared by every voice, regardless of which engine each one is
/// individually rendering (see `SynthVoice.currentEngine`) — Tone/Decay
/// apply universally rather than per-layer. Written from the main thread,
/// read once per sample on the audio thread — plain Float reads, no
/// locking, a one-block-stale value is inaudible.
struct VoiceParams {
    var cutoff: Float = 2_400   // Hz — subtractive/square filter brightness
    var decay: Float = 0.35     // 0...1 — "pluck" (0) to "pad" (1), drives sustain/release/attack together
}

extension Float {
    func clamped(_ lo: Float, _ hi: Float) -> Float { Swift.min(Swift.max(self, lo), hi) }
}

private enum EnvStage { case idle, attack, decay, sustain, release }

/// Minimal ADSR — same shape as Modula's `ADSRNode`, inlined per-voice
/// instead of routed through a generic node graph since Chordwright's signal
/// path is fixed, not user-patchable.
private struct Envelope {
    var stage: EnvStage = .idle
    var level: Float = 0
    private var releaseStartLevel: Float = 0

    mutating func noteOn() { stage = .attack }
    mutating func noteOff() { releaseStartLevel = level; stage = .release }
    var isIdle: Bool { stage == .idle }

    mutating func advance(attack: Float, decay: Float, sustain: Float, release: Float, sampleRate: Float) -> Float {
        switch stage {
        case .idle:
            level = 0
        case .attack:
            level += 1 / max(attack * sampleRate, 1)
            if level >= 1 { level = 1; stage = .decay }
        case .decay:
            level -= (1 - sustain) / max(decay * sampleRate, 1)
            if level <= sustain { level = sustain; stage = .sustain }
        case .sustain:
            level = sustain
        case .release:
            level -= max(releaseStartLevel, 0.0001) / max(release * sampleRate, 1)
            if level <= 0 { level = 0; stage = .idle }
        }
        return level
    }
}

/// One synthesis voice. `groupID` ties a voice to whichever pad or loop step
/// triggered it, so `PolySynth` can release exactly the right notes later
/// without tracking pitches by hand.
final class SynthVoice {
    private(set) var groupID: Int?
    private var midi: Int?
    /// Baked in at `noteOn`/`addNote` time, NOT read from a shared pool-wide
    /// params struct — this is what lets multiple engines sound layered at
    /// once: each voice in the pool can independently be a Sub voice, an FM
    /// voice, a Reed voice, etc., all triggered from the same chord press.
    private(set) var currentEngine: SynthEngineType = .subtractive

    private var phaseA: Double = 0
    private var phaseB: Double = 0
    private var modPhase: Double = 0
    private var filterLow: Float = 0
    private var filterBand: Float = 0

    private var pwmPhase: Double = 0 // Square engine's slow duty-cycle sweep

    // Pluck engine (Karplus-Strong): a noise burst re-circulated through a
    // short delay line. `pluckNeedsInit` is a real flag (not "does the
    // buffer length match the current freq") so a glide's continuously
    // changing frequency doesn't re-excite the string every sample —
    // the string is only plucked fresh on `noteOn`, exactly like a real one.
    private var pluckBuffer: [Float] = []
    private var pluckIndex: Int = 0
    private var pluckNeedsInit = true

    private var ampEnv = Envelope()
    private var modEnv = Envelope() // reed engine's fast percussive FM "bark"

    // Glide (glissando): `currentPitch` is what's actually sounding, sliding
    // linearly toward `targetPitch` over `glideDurationSamples`. Fresh
    // `noteOn` pins both to the same value (instant, no glide). `glideTo`
    // is the only thing that ever creates a gap between them.
    private var currentPitch: Double = 0
    private var targetPitch: Double = 0
    private var glideStartPitch: Double = 0
    private var glideDurationSamples: Double = 0
    private var glideElapsedSamples: Double = 0

    var isIdle: Bool { groupID == nil }
    var currentLevel: Float { ampEnv.level }
    /// Current sounding pitch (mid-glide if gliding) — used to pair up
    /// old-chord voices with new-chord notes by pitch order for a glissando.
    var pitch: Double { currentPitch }

    func noteOn(midi: Int, groupID: Int, engine: SynthEngineType) {
        self.midi = midi
        self.groupID = groupID
        currentEngine = engine
        currentPitch = Double(midi)
        targetPitch = Double(midi)
        glideDurationSamples = 0
        glideElapsedSamples = 0
        phaseA = 0; phaseB = 0; modPhase = 0
        filterLow = 0; filterBand = 0
        pluckNeedsInit = true
        ampEnv.noteOn()
        modEnv.noteOn()
    }

    /// Re-pitches an already-sounding voice toward `midi` over `glideSeconds`
    /// instead of restarting it — no phase/envelope reset, so the note keeps
    /// ringing through the transition. Used for the glissando drag gesture
    /// (as opposed to `noteOn`'s full fresh-attack reset for a plain tap).
    func glideTo(midi: Int, groupID: Int, glideSeconds: Float, sampleRate: Float) {
        self.midi = midi
        self.groupID = groupID
        glideStartPitch = currentPitch
        targetPitch = Double(midi)
        glideDurationSamples = Double(max(glideSeconds, 0.001) * sampleRate)
        glideElapsedSamples = 0
    }

    func noteOff() {
        ampEnv.noteOff()
        modEnv.noteOff()
    }

    /// Immediately silences the voice, bypassing the release stage — for a
    /// global "panic" stop-everything action, not a musical note-off.
    /// Frees it for reuse right away (`render` returns 0 as soon as `midi`
    /// is nil); `noteOn` resets the rest of the state cleanly on next use.
    func hardStop() {
        groupID = nil
        midi = nil
    }

    /// Changes which group this voice is tagged under, without touching
    /// pitch, phase, or envelope — used when an arpeggiator's identity
    /// moves to a new pad mid-note (see `PolySynth.retagGroup`), so the
    /// currently-sounding note keeps ringing exactly as it was but is still
    /// findable by a later release/retarget under the new tag.
    func retag(to groupID: Int) {
        self.groupID = groupID
    }

    func render(params: VoiceParams, sampleRate: Float) -> Float {
        guard midi != nil else { return 0 }

        if glideElapsedSamples < glideDurationSamples {
            glideElapsedSamples += 1
            let t = glideElapsedSamples / glideDurationSamples
            currentPitch = glideStartPitch + (targetPitch - glideStartPitch) * t
        } else {
            currentPitch = targetPitch
        }
        let freq = 440.0 * pow(2.0, (currentPitch - 69.0) / 12.0)

        let attack: Float = 0.005 + params.decay * 0.05
        let sustain: Float = 0.15 + params.decay * 0.65
        let release: Float = 0.15 + params.decay * 2.35
        let amp = ampEnv.advance(attack: attack, decay: 0.05, sustain: sustain, release: release, sampleRate: sampleRate)

        let sample: Float
        switch currentEngine {
        case .subtractive:
            sample = renderSubtractive(freq: freq, cutoff: params.cutoff, sampleRate: sampleRate)
        case .fm:
            sample = renderFM(freq: freq, sampleRate: sampleRate)
        case .reed:
            sample = renderReed(freq: freq, sampleRate: sampleRate)
        case .square:
            sample = renderSquare(freq: freq, cutoff: params.cutoff, sampleRate: sampleRate)
        case .bell:
            sample = renderBell(freq: freq, sampleRate: sampleRate)
        case .pluck:
            sample = renderPluck(freq: freq, sampleRate: sampleRate)
        }

        let result = sample * amp
        if ampEnv.isIdle {
            groupID = nil
            self.midi = nil
        }
        return result
    }

    /// Two detuned sawtooths through a Chamberlin state-variable lowpass —
    /// same stability clamp on `f` as Modula's `FilterNode` (direct-form SVF
    /// only stays numerically stable for cutoff well short of fs/4).
    private func renderSubtractive(freq: Double, cutoff: Float, sampleRate: Float) -> Float {
        let sr = Double(sampleRate)
        phaseA += freq / sr; if phaseA >= 1 { phaseA -= 1 }
        phaseB += (freq * pow(2.0, 7.0 / 1200.0)) / sr; if phaseB >= 1 { phaseB -= 1 }
        let mixed = Float((2 * phaseA - 1) + (2 * phaseB - 1)) * 0.5

        let resonance: Float = 0.15
        let q = 1 - resonance
        let f = (2 * sinf(Float.pi * cutoff / sampleRate)).clamped(0, 1.9)
        filterLow += f * filterBand
        let high = mixed - filterLow - q * filterBand
        filterBand += f * high
        if !filterLow.isFinite || !filterBand.isFinite { filterLow = 0; filterBand = 0 }
        return filterLow
    }

    /// Classic 2-operator FM: sine carrier phase-modulated by a sine
    /// modulator at a fixed 2:1 ratio and moderate index for a bright,
    /// bell-ish steady-state timbre.
    private func renderFM(freq: Double, sampleRate: Float) -> Float {
        let sr = Double(sampleRate)
        let modIndex = 3.5
        modPhase += (freq * 2.0) / sr; if modPhase >= 1 { modPhase -= 1 }
        let modValue = sin(modPhase * 2 * .pi)

        phaseA += freq / sr; if phaseA >= 1 { phaseA -= 1 }
        return Float(sin(phaseA * 2 * .pi + modValue * modIndex))
    }

    /// Electric-piano-style "bark": the modulator's own index follows a
    /// fast, independent decay envelope (not the shared amp ADSR) so each
    /// note opens bright and mellows within ~100ms, then the carrier rings
    /// on under the main envelope — the classic DX-era EP mechanism.
    private func renderReed(freq: Double, sampleRate: Float) -> Float {
        let sr = Double(sampleRate)
        let modIndexPeak: Float = 6.0
        let modAmp = modEnv.advance(attack: 0.002, decay: 0.11, sustain: 0, release: 0.08, sampleRate: sampleRate)

        modPhase += freq / sr; if modPhase >= 1 { modPhase -= 1 }
        let modValue = sin(modPhase * 2 * .pi) * Double(modAmp * modIndexPeak)

        phaseA += freq / sr; if phaseA >= 1 { phaseA -= 1 }
        return Float(sin(phaseA * 2 * .pi + modValue))
    }

    /// A single pulse wave whose duty cycle sweeps slowly (an independent
    /// ~0.25Hz LFO, not tied to any knob) through the same lowpass as
    /// Subtractive — hollower and more reedy than the saw pair, with a
    /// gentle built-in movement instead of a static timbre.
    private func renderSquare(freq: Double, cutoff: Float, sampleRate: Float) -> Float {
        let sr = Double(sampleRate)
        phaseA += freq / sr; if phaseA >= 1 { phaseA -= 1 }
        pwmPhase += 0.25 / sr; if pwmPhase >= 1 { pwmPhase -= 1 }
        let dutyCycle = 0.5 + 0.2 * sin(pwmPhase * 2 * .pi) // sweeps 0.3...0.7
        let raw: Float = phaseA < dutyCycle ? 1.0 : -1.0

        let resonance: Float = 0.15
        let q = 1 - resonance
        let f = (2 * sinf(Float.pi * cutoff / sampleRate)).clamped(0, 1.9)
        filterLow += f * filterBand
        let high = raw - filterLow - q * filterBand
        filterBand += f * high
        if !filterLow.isFinite || !filterBand.isFinite { filterLow = 0; filterBand = 0 }
        return filterLow
    }

    /// 2-operator FM at a fixed *inharmonic* ratio (unlike FM's clean 2:1) —
    /// non-integer partials give a metallic, glass/bell-like character
    /// instead of a musical/harmonic one.
    private func renderBell(freq: Double, sampleRate: Float) -> Float {
        let sr = Double(sampleRate)
        let modRatio = 3.01
        let modIndex = 2.2
        modPhase += (freq * modRatio) / sr; if modPhase >= 1 { modPhase -= 1 }
        let modValue = sin(modPhase * 2 * .pi)

        phaseA += freq / sr; if phaseA >= 1 { phaseA -= 1 }
        return Float(sin(phaseA * 2 * .pi + modValue * modIndex))
    }

    /// Karplus-Strong plucked string: a burst of noise sized to the target
    /// pitch's period, re-circulated through itself with light averaging +
    /// damping each pass — the classic cheap recipe for a natural plucked
    /// decay, completely different in character from the other 5 engines
    /// (all continuous oscillators). Only re-excited on a genuinely fresh
    /// `noteOn`, so a glide's shifting frequency doesn't keep re-plucking
    /// it — same as a real string, which doesn't retune smoothly either.
    private func renderPluck(freq: Double, sampleRate: Float) -> Float {
        let length = max(2, Int(Double(sampleRate) / freq))
        if pluckNeedsInit {
            pluckBuffer = (0..<length).map { _ in Float.random(in: -1...1) }
            pluckIndex = 0
            pluckNeedsInit = false
        }
        guard !pluckBuffer.isEmpty else { return 0 }
        let i0 = pluckIndex
        let i1 = (pluckIndex + 1) % pluckBuffer.count
        let sample = pluckBuffer[i0]
        let damping: Float = 0.996
        pluckBuffer[i0] = (pluckBuffer[i0] + pluckBuffer[i1]) * 0.5 * damping
        pluckIndex = i1
        return sample
    }
}
