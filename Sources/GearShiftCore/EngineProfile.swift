import Foundation

/// The engine a gear's model sounds like when shifted into: its size, how high it revs, and the
/// tone of its exhaust. Values at `intensity` 0 (medium effort) and 1 (max effort); in between
/// they're interpolated.
public struct EngineProfile: Hashable {
    public let name: String
    public let cylinders: Int
    /// A two-stroke fires every cylinder once per revolution, a four-stroke every other one.
    public let isTwoStroke: Bool
    public let idleRPM: Double
    public let peakRPM: ClosedRange<Double>
    /// Seconds from idle to the top of the blip.
    public let riseTime: ClosedRange<Double>
    public let duration: ClosedRange<Double>
    /// Oscillator mix: sawtooth is clean, square is buzzy, the second bank is a slightly detuned
    /// saw for a V12's two cylinder banks.
    public let sawMix: Double
    public let squareMix: Double
    public let secondBankMix: Double
    /// Sine at half the firing frequency.
    public let subBassMix: Double
    /// Relative loudness of each firing, in firing order; with `burbleDepth` it makes a V8 lope.
    public let firingPattern: [Double]
    public let burbleDepth: Double
    /// Filtered noise for intake and exhaust.
    public let noiseMix: Double
    /// Low-pass cutoff = floor + multiple × firing frequency, so the tone brightens as it revs.
    /// Floors sit well above 300 Hz so the character is in the harmonics laptop speakers can play.
    public let cutoffFloor: Double
    public let cutoffMultiple: Double
    public let resonance: Double
    /// Soft saturation (tanh) gain: adds harmonics and loudness without hard clipping.
    public let drive: Double
    /// High-pass on the tone: lows a laptop can't play would only eat headroom.
    public let bodyCutoff: Double
    /// Peak amplitude at intensity 0; max effort adds `SoundSynth.intensityLevelBoost`.
    public let level: Double
    public let noiseSeed: UInt64

    /// Firings per second at `rpm`: rpm/60 × cylinders/2 for a four-stroke.
    public func firingFrequency(rpm: Double) -> Double {
        rpm / 60 * Double(cylinders) / (isTwoStroke ? 1 : 2)
    }

    /// Small two-cylinder two-stroke scooter: high-pitched, buzzy, light and short.
    public static let scooter = EngineProfile(
        name: "scooter", cylinders: 2, isTwoStroke: true,
        idleRPM: 2_400, peakRPM: 8_400...10_200, riseTime: 0.13...0.16, duration: 0.5...0.62,
        sawMix: 0.3, squareMix: 0.7, secondBankMix: 0, subBassMix: 0,
        firingPattern: [1, 0.8], burbleDepth: 0.25, noiseMix: 0.35,
        cutoffFloor: 1_000, cutoffMultiple: 6, resonance: 1.1, drive: 1.6, bodyCutoff: 220,
        level: 0.4, noiseSeed: 0x5C00_7E12
    )

    /// Smooth inline four: mid pitch, clean.
    public static let inlineFour = EngineProfile(
        name: "inline-four", cylinders: 4, isTwoStroke: false,
        idleRPM: 1_100, peakRPM: 5_600...6_900, riseTime: 0.2...0.26, duration: 0.72...0.9,
        sawMix: 0.85, squareMix: 0.15, secondBankMix: 0, subBassMix: 0.04,
        firingPattern: [1, 0.94, 0.98, 0.92], burbleDepth: 0.1, noiseMix: 0.15,
        cutoffFloor: 1_000, cutoffMultiple: 4.5, resonance: 0.9, drive: 1.5, bodyCutoff: 200,
        level: 0.4, noiseSeed: 0x1414_0004
    )

    /// Big cross-plane V8: low and rumbly, but heard through its harmonics and the lopey burble of
    /// its uneven firing order modulating them, with a growly resonant filter; a little sub-bass
    /// for headphones.
    public static let v8 = EngineProfile(
        name: "v8", cylinders: 8, isTwoStroke: false,
        idleRPM: 900, peakRPM: 3_300...4_200, riseTime: 0.24...0.3, duration: 0.88...1.06,
        sawMix: 0.85, squareMix: 0.15, secondBankMix: 0, subBassMix: 0.1,
        firingPattern: [1, 0.5, 0.85, 0.62, 0.95, 0.45, 0.9, 0.58], burbleDepth: 0.65, noiseMix: 0.12,
        cutoffFloor: 600, cutoffMultiple: 2.6, resonance: 1.4, drive: 2.2, bodyCutoff: 160,
        level: 0.42, noiseSeed: 0x0008_BEEF
    )

    /// V12 supercar: rich harmonics, climbs high and screams; the longest.
    public static let v12 = EngineProfile(
        name: "v12", cylinders: 12, isTwoStroke: false,
        idleRPM: 1_000, peakRPM: 7_800...9_000, riseTime: 0.42...0.5, duration: 0.96...1.1,
        sawMix: 0.75, squareMix: 0.15, secondBankMix: 0.35, subBassMix: 0.03,
        firingPattern: [1, 0.96, 0.99, 0.95, 1, 0.97], burbleDepth: 0.08, noiseMix: 0.1,
        cutoffFloor: 700, cutoffMultiple: 3.4, resonance: 0.95, drive: 1.3, bodyCutoff: 220,
        level: 0.38, noiseSeed: 0x0012_F00D
    )

    /// Neutral: a small, quick blip from idle.
    public static let idle = EngineProfile(
        name: "idle", cylinders: 4, isTwoStroke: false,
        idleRPM: 1_000, peakRPM: 2_800...3_200, riseTime: 0.08...0.09, duration: 0.38...0.44,
        sawMix: 0.75, squareMix: 0.25, secondBankMix: 0, subBassMix: 0.04,
        firingPattern: [1, 0.85, 0.95, 0.8], burbleDepth: 0.3, noiseMix: 0.2,
        cutoffFloor: 1_100, cutoffMultiple: 6, resonance: 1.0, drive: 2.4, bodyCutoff: 200,
        level: 0.38, noiseSeed: 0x1D1E_0000
    )

    public static let all: [EngineProfile] = [.scooter, .inlineFour, .v8, .v12, .idle]

    /// The engine for a `/model` alias or id, e.g. `opus`, `claude-opus-5-5` or `opus[1m]`;
    /// `default` idles, and anything unrecognized sounds like Sonnet's.
    public static func forModel(_ model: String) -> EngineProfile {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name == "default" { return .idle }
        if name.contains("fable") { return .v12 }
        if name.contains("opus") { return .v8 }
        if name.contains("haiku") { return .scooter }
        return .inlineFour
    }

    /// How hard the engine revs, 0...1: low and medium (and auto, nil) 0, high and xhigh 0.5,
    /// max 1.
    public static func intensity(for effort: Effort?) -> Double {
        switch effort {
        case nil, .low, .medium: 0
        case .high, .xhigh: 0.5
        case .max: 1
        }
    }
}
