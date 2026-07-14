import Foundation

/// Fixed pool of voices shared by both live pad presses and the loop's
/// scheduled steps. A `groupID` (pad index, or `1000 + step` for the loop)
/// ties a set of notes together so releasing "whatever pad 3 is holding" or
/// "whatever step 7 triggered" doesn't require tracking pitches by hand.
final class PolySynth {
    var params = VoiceParams()

    private var voices: [SynthVoice]

    /// 24 voices was plenty when only one engine could ever be active at a
    /// time. Now that engines layer (a 7-note chord across all 6 active
    /// engines is 42 voices), the pool needs real headroom — sized for one
    /// full worst-case chord across every engine plus some slack for
    /// overlap with the loop/other pads, not for many simultaneous
    /// worst-case chords (voice stealing degrades gracefully beyond that).
    init(voiceCount: Int = 48) {
        voices = (0..<voiceCount).map { _ in SynthVoice() }
    }

    func trigger(midiNotes: [Int], groupID: Int, engines: Set<SynthEngineType>) {
        release(groupID: groupID)
        for midi in midiNotes {
            for engine in engines {
                addNote(midi, groupID: groupID, engine: engine)
            }
        }
    }

    /// Adds one voice under `groupID` WITHOUT releasing whatever else that
    /// group already holds — used to build a chord up incrementally (strum,
    /// slop, arp step, or an extra engine layer) rather than replacing it
    /// all at once like `trigger`.
    func addNote(_ midi: Int, groupID: Int, engine: SynthEngineType) {
        let voice = voices.first(where: { $0.isIdle }) ?? quietestVoice()
        voice?.noteOn(midi: midi, groupID: groupID, engine: engine)
    }

    func release(groupID: Int) {
        for voice in voices where voice.groupID == groupID {
            voice.noteOff()
        }
    }

    /// Re-pitches the voices currently under `fromGroupID` toward
    /// `midiNotes` — paired index-wise, old voices sorted by their current
    /// pitch against new notes sorted ascending — and retags them to
    /// `toGroupID`, instead of releasing and re-triggering. A glissando
    /// between two chords rather than a hard cut. Done **per engine**, not
    /// across the whole group at once: with layered engines, `fromGroupID`
    /// might hold e.g. 4 Sub voices and 4 FM voices at the same 4 pitches —
    /// pairing them all together by pitch alone would blend engines
    /// incorrectly (a Sub voice could end up gliding to where an FM voice
    /// "belongs"). Pairing within each engine separately keeps every layer
    /// gliding independently but consistently, same as it always sounded.
    ///
    /// Voice count stays locked to whatever was already sounding, per
    /// engine: if the new chord has *more* notes than a given engine had
    /// voices for, that engine's extras are simply not played — a fresh
    /// voice attacking mid-slide would read as a pop, not a glide. Extra old
    /// voices for an engine release normally (letting go doesn't have that
    /// problem).
    func glideChord(fromGroupID: Int, toGroupID: Int, midiNotes: [Int], engines: Set<SynthEngineType>, glideSeconds: Float, sampleRate: Float) {
        let newNotes = midiNotes.sorted()
        for engine in engines {
            let oldVoices = voices
                .filter { $0.groupID == fromGroupID && $0.currentEngine == engine }
                .sorted { $0.pitch < $1.pitch }
            let pairCount = min(oldVoices.count, newNotes.count)

            for i in 0..<pairCount {
                oldVoices[i].glideTo(midi: newNotes[i], groupID: toGroupID, glideSeconds: glideSeconds, sampleRate: sampleRate)
            }
            if oldVoices.count > pairCount {
                for voice in oldVoices[pairCount...] {
                    voice.noteOff()
                }
            }
        }
    }

    func releaseAll() {
        for voice in voices { voice.noteOff() }
    }

    /// Retags any voice currently under `from` to `to`, untouched otherwise
    /// — used when an arpeggiator's identity moves to a new pad mid-note,
    /// so its currently-sounding voice stays findable by a later
    /// release/retarget instead of getting orphaned under the old tag.
    func retagGroup(from: Int, to: Int) {
        for voice in voices where voice.groupID == from {
            voice.retag(to: to)
        }
    }

    /// Immediately silences every voice — the panic/stop-everything action,
    /// not a musical release.
    func hardStopAll() {
        for voice in voices { voice.hardStop() }
    }

    private func quietestVoice() -> SynthVoice? {
        voices.min(by: { $0.currentLevel < $1.currentLevel })
    }

    /// Mono render — the effects chain downstream is what gives the output
    /// its stereo width (chorus in particular).
    func render(frameCount: Int, sampleRate: Float) -> [Float] {
        var out = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            var sum: Float = 0
            for voice in voices {
                sum += voice.render(params: params, sampleRate: sampleRate)
            }
            out[i] = sum * 0.22
        }
        return out
    }
}
