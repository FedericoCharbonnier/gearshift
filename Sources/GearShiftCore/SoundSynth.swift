import Foundation

/// Mono Float PCM for the shift sounds: a gearbox clunk, then an engine rev in the character of
/// the model shifted into. Everything is deterministic (noise is seeded) and starts and ends at 0.
public enum SoundSynth {
    public static let sampleRate: Double = 44_100
    /// The engine rev starts this long after the clunk.
    public static let engineDelay: Double = 0.09
    /// Extra peak level at max effort.
    public static let intensityLevelBoost: Double = 0.04
    /// Ceiling for the clunk and rev mixed together.
    static let mixCeiling: Float = 0.48

    /// The whole shift: the clunk, overlapped by the engine rev from `engineDelay`.
    public static func shiftSound(profile: EngineProfile, intensity: Double) -> [Float] {
        let delay = Int((engineDelay * sampleRate).rounded())
        return mix(gearboxClunk(), engineRev(profile: profile, intensity: intensity), offset: delay)
    }

    // MARK: Gearbox

    /// A metallic clack as the synchro catches, a smaller one as the gear engages. Each is a
    /// broadband click and a 1–4 kHz ring (what laptop speakers carry) over a small low thunk.
    public static func gearboxClunk() -> [Float] {
        let duration = 0.18
        let count = Int((duration * sampleRate).rounded())
        var samples = [Float](repeating: 0, count: count)
        var noise = SeededNoise(seed: 0xC1AC_C1AC)
        addClack(to: &samples, at: 0, scale: 1, pitch: 1, noise: &noise)
        addClack(to: &samples, at: 0.034, scale: 0.55, pitch: 0.92, noise: &noise)
        applyFades(to: &samples, fadeIn: 0.0015, fadeOut: 0.03)
        normalize(&samples, peak: 0.42)
        return samples
    }

    /// One strike: a band-passed noise click, a few inharmonic ringing partials, and a sine thunk
    /// sweeping down.
    private static func addClack(to samples: inout [Float], at start: Double, scale: Double, pitch: Double, noise: inout SeededNoise) {
        let partials: [(frequency: Double, amplitude: Double, decay: Double)] = [
            (1_180, 0.5, 0.032), (1_730, 0.42, 0.024), (2_640, 0.34, 0.017), (3_910, 0.2, 0.011),
        ]
        var tick = Biquad()
        tick.setBandPass(cutoff: 2_800 * pitch, q: 0.55)
        var thunkPhase = 0.0
        let first = Int((start * sampleRate).rounded())
        for index in first..<samples.count {
            let time = Double(index - first) / sampleRate
            thunkPhase += expRamp(170 * pitch, 60, time / 0.06) / sampleRate
            let thunk = 0.3 * sin(2 * .pi * thunkPhase) * exp(-time / 0.03)
            let ring = partials.reduce(0.0) { sum, partial in
                sum + partial.amplitude * sin(2 * .pi * partial.frequency * pitch * time) * exp(-time / partial.decay)
            }
            let click = tick.process(noise.next()) * exp(-time / 0.005)
            samples[index] += Float(scale * (thunk + ring + 2.2 * click))
        }
    }

    // MARK: Engine

    /// A blip of the throttle: RPM climbs from idle to the profile's peak, then settles back while
    /// the sound fades. `intensity` (0...1, see `EngineProfile.intensity(for:)`) raises the peak
    /// RPM, the length and the level.
    public static func engineRev(profile: EngineProfile, intensity: Double) -> [Float] {
        let amount = min(1, max(0, intensity))
        let curve = RPMCurve(profile: profile, amount: amount)
        let count = Int((curve.duration * sampleRate).rounded())
        var samples = [Float](repeating: 0, count: count)
        var voice = EngineVoice(profile: profile)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let rpm = curve.rpm(at: time)
            let throttle = (rpm - profile.idleRPM) / (curve.peakRPM - profile.idleRPM)
            samples[index] = Float(voice.next(rpm: rpm) * (0.6 + 0.4 * throttle))
        }
        applyFades(to: &samples, fadeIn: 0.012, fadeOut: min(0.14, curve.duration * 0.25))
        normalize(&samples, peak: profile.level + intensityLevelBoost * amount)
        return samples
    }

    /// Idle → peak with an ease-out, then an exponential fall toward just above idle.
    struct RPMCurve {
        let idleRPM: Double
        let peakRPM: Double
        let settleRPM: Double
        let riseTime: Double
        let duration: Double

        init(profile: EngineProfile, amount: Double) {
            idleRPM = profile.idleRPM
            peakRPM = lerp(profile.peakRPM, amount)
            settleRPM = profile.idleRPM * 1.2
            riseTime = lerp(profile.riseTime, amount)
            duration = lerp(profile.duration, amount)
        }

        func rpm(at time: Double) -> Double {
            if time < riseTime {
                let progress = time / riseTime
                return idleRPM + (peakRPM - idleRPM) * (1 - pow(1 - progress, 2.2))
            }
            let fallTime = max(0.05, (duration - riseTime) * 0.4)
            return settleRPM + (peakRPM - settleRPM) * exp(-(time - riseTime) / fallTime)
        }
    }

    /// Oscillators, burble, noise and the RPM-tracking low-pass for one engine.
    struct EngineVoice {
        let profile: EngineProfile
        var phase = 0.0
        var bankPhase = 0.25
        var noise: SeededNoise
        var noiseSmoothed = 0.0
        var filter = Biquad()
        var bodyFilter = Biquad()
        var dcBlocker = DCBlocker()

        init(profile: EngineProfile) {
            self.profile = profile
            noise = SeededNoise(seed: profile.noiseSeed)
            bodyFilter.setHighPass(cutoff: profile.bodyCutoff, q: 0.707)
        }

        mutating func next(rpm: Double) -> Double {
            let firing = profile.firingFrequency(rpm: rpm)
            let step = firing / sampleRate
            phase += step
            bankPhase += step * 1.004
            let fraction = phase - floor(phase)
            var tone = profile.sawMix * polyBLEPSaw(fraction, step) + profile.squareMix * polyBLEPSquare(fraction, step)
            if profile.secondBankMix > 0 {
                tone += profile.secondBankMix * polyBLEPSaw(bankPhase - floor(bankPhase), step * 1.004)
            }
            tone *= 1 - profile.burbleDepth * (1 - firingWeight())
            // Exhaust puffs: noise loudest right after each firing.
            noiseSmoothed += 0.25 * (noise.next() - noiseSmoothed)
            let exhaust = profile.noiseMix * noiseSmoothed * (0.3 + pow(1 - fraction, 4))
            filter.setLowPass(cutoff: min(0.42 * sampleRate, profile.cutoffFloor + profile.cutoffMultiple * firing), q: profile.resonance)
            // Saturating after the high-pass rounds off the pulses it leaves, for more loudness
            // per unit of peak, and adds harmonics.
            let saturated = tanh(profile.drive * bodyFilter.process(filter.process(tone + exhaust)))
            let subBass = profile.subBassMix * sin(.pi * phase)
            return dcBlocker.process(saturated + subBass)
        }

        /// This firing's weight in the firing order, eased into the next one so it doesn't click.
        private func firingWeight() -> Double {
            let pattern = profile.firingPattern
            let firingIndex = Int(floor(phase))
            let current = pattern[firingIndex % pattern.count]
            let upcoming = pattern[(firingIndex + 1) % pattern.count]
            let ease = 0.5 - 0.5 * cos(.pi * (phase - floor(phase)))
            return current + (upcoming - current) * ease
        }
    }

    // MARK: Building blocks

    /// Adds `overlay` into `base` from `offset` samples, then scales the result down if it would
    /// peak above `mixCeiling`.
    static func mix(_ base: [Float], _ overlay: [Float], offset: Int) -> [Float] {
        var result = base + [Float](repeating: 0, count: max(0, offset + overlay.count - base.count))
        for (index, sample) in overlay.enumerated() {
            result[offset + index] += sample
        }
        if let peak = result.map(abs).max(), peak > mixCeiling {
            let scale = mixCeiling / peak
            result = result.map { $0 * scale }
        }
        return result
    }

    /// Raised-cosine fades so the first and last samples are exactly 0.
    static func applyFades(to samples: inout [Float], fadeIn: Double, fadeOut: Double) {
        guard !samples.isEmpty else { return }
        let inCount = max(1, Int(fadeIn * sampleRate))
        let outCount = max(1, Int(fadeOut * sampleRate))
        for index in 0..<min(inCount, samples.count) {
            samples[index] *= Float(0.5 - 0.5 * cos(.pi * Double(index) / Double(inCount)))
        }
        let last = samples.count - 1
        for offset in 0..<min(outCount, samples.count) {
            samples[last - offset] *= Float(0.5 - 0.5 * cos(.pi * Double(offset) / Double(outCount)))
        }
    }

    static func normalize(_ samples: inout [Float], peak target: Double) {
        guard let peak = samples.map(abs).max(), peak > 0 else { return }
        let scale = Float(target) / peak
        for index in samples.indices {
            samples[index] *= scale
        }
    }

    /// Band-limited sawtooth: `fraction` is the phase in 0..<1, `step` the phase advance per sample.
    static func polyBLEPSaw(_ fraction: Double, _ step: Double) -> Double {
        2 * fraction - 1 - polyBLEP(fraction, step)
    }

    static func polyBLEPSquare(_ fraction: Double, _ step: Double) -> Double {
        let shifted = fraction + 0.5 - floor(fraction + 0.5)
        return (fraction < 0.5 ? 1 : -1) + polyBLEP(fraction, step) - polyBLEP(shifted, step)
    }

    /// Smooths the step a naive waveform takes at phase 0.
    private static func polyBLEP(_ fraction: Double, _ step: Double) -> Double {
        if fraction < step {
            let x = fraction / step
            return x + x - x * x - 1
        }
        if fraction > 1 - step {
            let x = (fraction - 1) / step
            return x * x + x + x + 1
        }
        return 0
    }

    /// Web Audio's exponentialRampToValueAtTime; `progress` is clamped to 0...1.
    static func expRamp(_ from: Double, _ to: Double, _ progress: Double) -> Double {
        from * pow(to / from, min(1, max(0, progress)))
    }

    static func lerp(_ range: ClosedRange<Double>, _ amount: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * amount
    }
}

/// Xorshift white noise in -1...1, the same for the same seed.
struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 52) - 1
    }
}

/// RBJ cookbook biquad, direct form I (steady when its coefficients change every sample).
struct Biquad {
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func setLowPass(cutoff: Double, q: Double) {
        let (cosine, alpha) = Self.terms(cutoff: cutoff, q: q)
        let a0 = 1 + alpha
        b0 = (1 - cosine) / 2 / a0
        b1 = (1 - cosine) / a0
        b2 = b0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func setHighPass(cutoff: Double, q: Double) {
        let (cosine, alpha) = Self.terms(cutoff: cutoff, q: q)
        let a0 = 1 + alpha
        b0 = (1 + cosine) / 2 / a0
        b1 = -(1 + cosine) / a0
        b2 = b0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    /// Unity gain at `cutoff`.
    mutating func setBandPass(cutoff: Double, q: Double) {
        let (cosine, alpha) = Self.terms(cutoff: cutoff, q: q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        (x2, x1, y2, y1) = (x1, input, y1, output)
        return output
    }

    private static func terms(cutoff: Double, q: Double) -> (cosine: Double, alpha: Double) {
        let omega = 2 * .pi * cutoff / SoundSynth.sampleRate
        return (cos(omega), sin(omega) / (2 * q))
    }
}

/// Removes DC and sub-audio drift (a one-pole high-pass around 20 Hz).
struct DCBlocker {
    private var previousInput = 0.0
    private var previousOutput = 0.0

    mutating func process(_ input: Double) -> Double {
        previousOutput = input - previousInput + 0.997 * previousOutput
        previousInput = input
        return previousOutput
    }
}
