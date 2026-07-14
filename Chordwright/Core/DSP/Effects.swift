import Foundation

/// Feedback delay line — same recipe as Modula's `DelayNode`, inlined here
/// since Chordwright's signal path is fixed rather than user-patchable.
final class SimpleDelay {
    private var buffer: [Float] = []
    private var writeIndex = 0

    var time: Float = 0.32   // seconds
    var feedback: Float = 0.32
    var mix: Float = 0

    func prepare(sampleRate: Float) {
        buffer = [Float](repeating: 0, count: Int(sampleRate * 1.5) + 1)
        writeIndex = 0
    }

    func process(_ input: Float, sampleRate: Float) -> Float {
        guard !buffer.isEmpty else { return input }
        let delaySamples = max(1, min(buffer.count - 1, Int(time * sampleRate)))
        var readIndex = writeIndex - delaySamples
        if readIndex < 0 { readIndex += buffer.count }
        let delayed = buffer[readIndex]

        let toWrite = input + delayed * feedback
        buffer[writeIndex] = toWrite.isFinite ? toWrite.clamped(-4, 4) : 0
        writeIndex = (writeIndex + 1) % buffer.count

        return input * (1 - mix) + delayed * mix
    }
}

/// Simplified Schroeder reverb (four combs + two allpasses) — same recipe as
/// Modula's `ReverbNode`.
final class SimpleReverb {
    private static let combLengths = [1_557, 1_617, 1_491, 1_422]
    private static let allpassLengths = [556, 225]

    private struct Comb { var buffer: [Float]; var index = 0; var filterState: Float = 0 }
    private struct Allpass { var buffer: [Float]; var index = 0 }

    private var combs: [Comb] = []
    private var allpasses: [Allpass] = []

    var decay: Float = 0.65
    var damping: Float = 0.5
    var mix: Float = 0

    func prepare(sampleRate: Float) {
        let ratio = Double(sampleRate) / 44_100.0
        combs = Self.combLengths.map { Comb(buffer: [Float](repeating: 0, count: max(1, Int(Double($0) * ratio)))) }
        allpasses = Self.allpassLengths.map { Allpass(buffer: [Float](repeating: 0, count: max(1, Int(Double($0) * ratio)))) }
    }

    func process(_ input: Float) -> Float {
        guard !combs.isEmpty, !allpasses.isEmpty else { return input }

        var combSum: Float = 0
        for c in combs.indices {
            let readIndex = combs[c].index
            let delayed = combs[c].buffer[readIndex]
            combs[c].filterState = delayed * (1 - damping) + combs[c].filterState * damping
            let toWrite = input + combs[c].filterState * decay
            combs[c].buffer[readIndex] = toWrite.isFinite ? toWrite.clamped(-4, 4) : 0
            combs[c].index = (readIndex + 1) % combs[c].buffer.count
            combSum += delayed
        }
        combSum /= Float(combs.count)

        var signal = combSum
        for a in allpasses.indices {
            let readIndex = allpasses[a].index
            let bufferOut = allpasses[a].buffer[readIndex]
            let gain: Float = 0.5
            let toWrite = signal + bufferOut * gain
            allpasses[a].buffer[readIndex] = toWrite.isFinite ? toWrite.clamped(-4, 4) : 0
            signal = bufferOut - signal * gain
            allpasses[a].index = (readIndex + 1) % allpasses[a].buffer.count
        }

        return input * (1 - mix) + signal * mix
    }
}

/// LFO-modulated short delay, read at two slightly offset phases for L/R —
/// mono in, stereo out. The cheap classic trick for turning one synth voice
/// into something that feels wide, which is most of what gives Chordwright's pads
/// their "instrument in a box" character rather than sounding thin.
final class SimpleChorus {
    private var buffer: [Float] = []
    private var writeIndex = 0
    private var sampleRate: Float = 44_100
    private var lfoPhase: Double = 0

    var rate: Float = 0.35   // Hz
    var depthMS: Float = 4
    var mix: Float = 0

    func prepare(sampleRate: Float) {
        self.sampleRate = sampleRate
        buffer = [Float](repeating: 0, count: Int(sampleRate * 0.05) + 1)
        writeIndex = 0
    }

    func process(_ input: Float) -> (left: Float, right: Float) {
        guard !buffer.isEmpty else { return (input, input) }
        buffer[writeIndex] = input
        lfoPhase += Double(rate) / Double(sampleRate)
        if lfoPhase >= 1 { lfoPhase -= 1 }

        let baseDelayMS = depthMS + 1
        let left = readTap(phaseOffset: 0, baseDelayMS: baseDelayMS)
        let right = readTap(phaseOffset: 0.25, baseDelayMS: baseDelayMS)

        writeIndex = (writeIndex + 1) % buffer.count
        return (input * (1 - mix) + left * mix, input * (1 - mix) + right * mix)
    }

    private func readTap(phaseOffset: Double, baseDelayMS: Float) -> Float {
        var phase = lfoPhase + phaseOffset
        if phase >= 1 { phase -= 1 }
        let lfo = Float(sin(phase * 2 * .pi))
        let delayMS = baseDelayMS + lfo * depthMS
        let delaySamples = Double(delayMS) * 0.001 * Double(sampleRate)

        var readPos = Double(writeIndex) - delaySamples
        while readPos < 0 { readPos += Double(buffer.count) }
        let i0 = Int(readPos) % buffer.count
        let i1 = (i0 + 1) % buffer.count
        let frac = Float(readPos - readPos.rounded(.down))
        return buffer[i0] * (1 - frac) + buffer[i1] * frac
    }
}
