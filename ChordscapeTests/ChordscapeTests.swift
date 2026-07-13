//
//  ChordscapeTests.swift
//  ChordscapeTests
//

import Testing
@testable import Chordscape

struct ChordscapeTests {

    @Test func triadIsAlwaysAtLeastThreeNotes() async throws {
        let chord = ChordEngine.generate(rootPitchClass: 0, scale: .major, degreeIndex: 0, complexity: 0)
        #expect(chord.midiNotes.count == 3)
    }

    @Test func highComplexityCanReachSevenths() async throws {
        var sawExtension = false
        for _ in 0..<20 {
            let chord = ChordEngine.generate(rootPitchClass: 0, scale: .major, degreeIndex: 0, complexity: 1.0)
            if chord.midiNotes.count > 3 { sawExtension = true; break }
        }
        #expect(sawExtension)
    }

    @Test func notesAreAscending() async throws {
        let chord = ChordEngine.generate(rootPitchClass: 4, scale: .dorian, degreeIndex: 2, complexity: 0.8)
        #expect(chord.midiNotes == chord.midiNotes.sorted())
    }

    @Test func labelStartsWithRootName() async throws {
        let chord = ChordEngine.generate(rootPitchClass: 0, scale: .major, degreeIndex: 0, complexity: 0)
        #expect(chord.label.hasPrefix("C"))
    }

    @Test func majorElevenIsSharpedNotNatural() async throws {
        // Cmaj7 stacked to the 11th should raise F -> F# (65 -> 66), not leave the "avoid note" F.
        let chord = ChordEngine.generate(rootPitchClass: 0, scale: .major, degreeIndex: 0, complexity: 1.0)
        if chord.midiNotes.count >= 6 {
            let eleventh = chord.midiNotes[5]
            #expect((eleventh - 48) % 12 == 6) // F# is 6 semitones above C, not 5 (natural F)
        }
    }

    @Test func minorElevenStaysNatural() async throws {
        // Dm7 (ii chord, minor 3rd) should keep a natural 11 (G, no clash).
        let chord = ChordEngine.generate(rootPitchClass: 0, scale: .major, degreeIndex: 1, complexity: 1.0)
        if chord.midiNotes.count >= 6 {
            let eleventh = chord.midiNotes[5]
            #expect((eleventh - 48) % 12 == 7) // G is 7 semitones above C (5 above D)
        }
    }

    @Test func voicingRootPositionIsUnchanged() async throws {
        let notes = [60, 64, 67]
        #expect(ChordEngine.applyVoicing(notes, steps: 0) == notes)
    }

    @Test func voicingPositiveStepsRaiseLowestNote() async throws {
        let notes = [60, 64, 67]
        let voiced = ChordEngine.applyVoicing(notes, steps: 1)
        #expect(voiced == [64, 67, 72]) // 60 -> 72, re-sorted
    }

    @Test func voicingNegativeStepsLowerHighestNote() async throws {
        let notes = [60, 64, 67]
        let voiced = ChordEngine.applyVoicing(notes, steps: -1)
        #expect(voiced == [55, 60, 64]) // 67 -> 55, re-sorted
    }

    @Test func slashLabelAddedWhenBassIsNotRoot() async throws {
        let label = ChordEngine.slashLabel("C", voicedNotes: [64, 67, 72], rootPitchClass: 0)
        #expect(label == "C/E")
    }

    @Test func slashLabelOmittedWhenBassIsRoot() async throws {
        let label = ChordEngine.slashLabel("C", voicedNotes: [60, 64, 67], rootPitchClass: 0)
        #expect(label == "C")
    }

    @Test func chromaticMinorHasMinorThird() async throws {
        let chord = ChordEngine.generateChromatic(rootPitchClass: 0, quality: .minor, complexity: 0)
        #expect(chord.midiNotes.count == 3)
        #expect((chord.midiNotes[1] - chord.midiNotes[0]) == 3) // minor 3rd
    }

    @Test func chromaticLabelReflectsQuality() async throws {
        let dim = ChordEngine.generateChromatic(rootPitchClass: 0, quality: .diminished, complexity: 0)
        #expect(dim.label == "Cdim")
        let sus = ChordEngine.generateChromatic(rootPitchClass: 0, quality: .sus, complexity: 0)
        #expect(sus.label == "Csus4")
    }
}
