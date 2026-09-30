import Foundation
@testable import GearShiftCore

func runSoundSynthTests() {
    suite("SoundSynth") {
        expectEqual(SoundSynth.expRamp(190, 70, 0), 190)
        expect(abs(SoundSynth.expRamp(190, 70, 1) - 70) < 1e-9, "ramp ends at its target")
        expect(abs(SoundSynth.expRamp(190, 70, 3) - 70) < 1e-9, "progress is clamped")

        let clunk = SoundSynth.gearboxClunk()
        expectGentle(clunk, "clunk")
        expect(duration(clunk) <= 0.2, "clunk is short: \(duration(clunk))s")
        expectEqual(SoundSynth.gearboxClunk(), clunk)
    }

    suite("SoundSynth.mix") {
        let mixed = SoundSynth.mix([0.1, 0.1, 0.1], [0.05, 0.05, 0.05], offset: 2)
        expectEqual(mixed.count, 5)
        expect(abs(mixed[2] - 0.15) < 1e-6 && abs(mixed[4] - 0.05) < 1e-6, "overlay added from the offset: \(mixed)")
        let loud = SoundSynth.mix([0.4], [0.4], offset: 0)
        expect(abs(loud[0] - 0.48) < 1e-6, "mix is scaled down to its ceiling: \(loud)")
    }

    suite("SoundSynth.engineRev") {
        for profile in EngineProfile.all {
            let medium = SoundSynth.engineRev(profile: profile, intensity: EngineProfile.intensity(for: .medium))
            let max = SoundSynth.engineRev(profile: profile, intensity: EngineProfile.intensity(for: .max))
            for (label, rev) in [("medium", medium), ("max", max)] {
                expectGentle(rev, "\(profile.name) \(label)")
                let shift = SoundSynth.shiftSound(profile: profile, intensity: label == "max" ? 1 : 0)
                expectGentle(shift, "\(profile.name) \(label) shift")
                expect(duration(shift) <= 1.2, "\(profile.name) \(label) shift lasts \(duration(shift))s")
            }
            expect(max.count >= medium.count, "\(profile.name): max effort revs at least as long")
            expect(peak(max) >= peak(medium), "\(profile.name): max effort revs at least as loud")
            expectEqual(SoundSynth.engineRev(profile: profile, intensity: 0), medium)
        }

        let centroids = Dictionary(uniqueKeysWithValues: [EngineProfile.scooter, .inlineFour, .v8, .v12].map { profile in
            (profile.name, spectralCentroid(SoundSynth.engineRev(profile: profile, intensity: 0)))
        })
        let (scooter, four, v8, v12) = (centroids["scooter"]!, centroids["inline-four"]!, centroids["v8"]!, centroids["v12"]!)
        expect(v8 < scooter, "opus's V8 is darker than haiku's scooter: \(v8) vs \(scooter) Hz")
        expect(v8 < four, "opus's V8 is darker than sonnet's four: \(v8) vs \(four) Hz")
        expect(v12 > four, "fable's V12 screams above sonnet's four: \(v12) vs \(four) Hz")
        expect(duration(SoundSynth.engineRev(profile: .v12, intensity: 1)) > duration(SoundSynth.engineRev(profile: .inlineFour, intensity: 1)), "V12 is the longest")
        expectEqual(SoundSynth.engineRev(profile: .v8, intensity: 7).count, SoundSynth.engineRev(profile: .v8, intensity: 1).count)
    }

    suite("EngineProfile") {
        let expected: [(String, EngineProfile)] = [
            ("haiku", .scooter), ("claude-haiku-4-5-20251001", .scooter),
            ("sonnet", .inlineFour), ("claude-sonnet-5", .inlineFour),
            ("opus", .v8), ("claude-opus-5-5", .v8), ("opus[1m]", .v8), ("OPUS", .v8),
            ("fable", .v12), ("claude-fable-5-1", .v12),
            ("default", .idle), (" Default ", .idle),
            ("gpt-5", .inlineFour), ("", .inlineFour),
        ]
        for (model, profile) in expected {
            expect(EngineProfile.forModel(model) == profile, "\(model) → \(EngineProfile.forModel(model).name), expected \(profile.name)")
        }

        expectEqual(EngineProfile.intensity(for: nil), 0)
        expectEqual(EngineProfile.intensity(for: .low), 0)
        expectEqual(EngineProfile.intensity(for: .medium), 0)
        expectEqual(EngineProfile.intensity(for: .high), 0.5)
        expectEqual(EngineProfile.intensity(for: .xhigh), 0.5)
        expectEqual(EngineProfile.intensity(for: .max), 1)

        expectEqual(EngineProfile.v8.firingFrequency(rpm: 6_000), 400)
        expectEqual(EngineProfile.inlineFour.firingFrequency(rpm: 6_000), 200)
        expectEqual(EngineProfile.scooter.firingFrequency(rpm: 6_000), 200)

        let defaults = GearConfig.defaults.gears
        let byGear: [Gear: EngineProfile] = [
            .reverse: .scooter, .neutral: .idle, .one: .inlineFour, .two: .inlineFour,
            .three: .v8, .four: .v8, .five: .v12,
        ]
        for (gear, profile) in byGear {
            expect(defaults[gear].map { EngineProfile.forModel($0.model) } == profile, "gear \(gear.rawValue) sounds like \(profile.name)")
        }
    }
}

/// Audible on laptop speakers (loud enough, most energy above 300 Hz) without clipping, and
/// silent at both ends so it doesn't click.
private func expectGentle(_ samples: [Float], _ label: String, file: StaticString = #fileID, line: UInt = #line) {
    expect(!samples.isEmpty, "\(label) is empty", file: file, line: line)
    let level = peak(samples)
    expect(level >= 0.3 && level <= 0.5, "\(label) peak \(level)", file: file, line: line)
    let high = highFrequencyShare(samples)
    expect(high >= 0.4, "\(label) has only \(high) of its energy above 300 Hz", file: file, line: line)
    expect(abs(samples.first ?? 1) < 0.001, "\(label) starts at 0", file: file, line: line)
    expect(abs(samples.last ?? 1) < 0.001, "\(label) ends at 0", file: file, line: line)
}

private func peak(_ samples: [Float]) -> Float {
    samples.map(abs).max() ?? 0
}

private func duration(_ samples: [Float]) -> Double {
    Double(samples.count) / SoundSynth.sampleRate
}

/// Share of the energy left after a first-order high-pass at 300 Hz, below which laptop speakers
/// play almost nothing.
private func highFrequencyShare(_ samples: [Float]) -> Double {
    let timeConstant = 1 / (2 * Double.pi * 300)
    let alpha = timeConstant / (timeConstant + 1 / SoundSynth.sampleRate)
    var (output, previousInput, highEnergy, totalEnergy) = (0.0, 0.0, 0.0, 0.0)
    for sample in samples.map(Double.init) {
        output = alpha * (output + sample - previousInput)
        previousInput = sample
        highEnergy += output * output
        totalEnergy += sample * sample
    }
    return totalEnergy > 0 ? highEnergy / totalEnergy : 0
}

/// Magnitude-weighted mean frequency, up to 8 kHz, over Hann-windowed frames.
private func spectralCentroid(_ samples: [Float]) -> Double {
    let frameLength = 2048
    let window: [Double] = (0..<frameLength).map { index in
        let angle = 2 * Double.pi * Double(index) / Double(frameLength)
        return 0.5 - 0.5 * cos(angle)
    }
    let binWidth = SoundSynth.sampleRate / Double(frameLength)
    var (weighted, total) = (0.0, 0.0)
    for start in stride(from: 0, to: samples.count - frameLength, by: frameLength) {
        let frame = (0..<frameLength).map { Double(samples[start + $0]) * window[$0] }
        for bin in stride(from: 2, to: Int(8_000 / binWidth), by: 2) {
            // Rotate a unit phasor instead of calling sin and cos per sample.
            let angle = -2 * Double.pi * Double(bin) / Double(frameLength)
            let (stepReal, stepImaginary) = (cos(angle), sin(angle))
            var (phasorReal, phasorImaginary, real, imaginary) = (1.0, 0.0, 0.0, 0.0)
            for sample in frame {
                real += sample * phasorReal
                imaginary += sample * phasorImaginary
                (phasorReal, phasorImaginary) = (phasorReal * stepReal - phasorImaginary * stepImaginary, phasorReal * stepImaginary + phasorImaginary * stepReal)
            }
            let magnitude = (real * real + imaginary * imaginary).squareRoot()
            weighted += magnitude * Double(bin) * binWidth
            total += magnitude
        }
    }
    return total > 0 ? weighted / total : 0
}
