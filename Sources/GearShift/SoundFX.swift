import AVFoundation
import GearShiftCore
import os

/// Plays the shift sound: the gearbox clunk and then an engine rev in the character of the gear's
/// model, revving harder with more effort. Each engine + effort is rendered once, on first use, into
/// one buffer.
///
/// The audio engine is built when a sound starts and thrown away once it has finished. An engine kept
/// from launch can go stale when the output device or its format changes (headphones, a Bluetooth
/// device, a display's speakers) and then fail to start; building it fresh avoids that, and an idle
/// GearShift doesn't keep the audio device awake.
@MainActor
final class SoundFX {
    private struct SoundKey: Hashable {
        let profile: EngineProfile
        let intensity: Double
    }

    private static let log = Logger(subsystem: "app.gearshift.GearShift", category: "sound")

    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!
    private var buffers: [SoundKey: AVAudioPCMBuffer] = [:]
    private var output: (engine: AVAudioEngine, player: AVAudioPlayerNode)?
    /// Bumped per scheduled sound; only the newest one's completion may tear the engine down.
    private var playCount = 0

    func play(shiftTo setting: GearSetting) {
        let key = SoundKey(profile: .forModel(setting.model), intensity: EngineProfile.intensity(for: setting.effort))
        guard let buffer = buffer(for: key) else {
            Self.log.error("couldn't make the sound buffer for \(setting.model, privacy: .public)")
            return
        }
        do {
            let (engine, player) = try runningOutput()
            playCount += 1
            let ticket = playCount
            player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.stopIfIdle(ticket: ticket) }
                }
            }
            if !player.isPlaying {
                player.play()
            }
            Self.log.debug("playing \(setting.model, privacy: .public) on \(engine.outputNode.outputFormat(forBus: 0), privacy: .public)")
        } catch {
            // Shifting still works, silently; the reason is in the log.
            Self.log.error("couldn't start audio: \(error.localizedDescription, privacy: .public)")
            tearDown()
        }
    }

    /// The current engine if it's still running, or a freshly built and started one.
    private func runningOutput() throws -> (AVAudioEngine, AVAudioPlayerNode) {
        if let output, output.engine.isRunning {
            return output
        }
        tearDown()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        output = (engine, player)
        return (engine, player)
    }

    private func stopIfIdle(ticket: Int) {
        guard ticket == playCount else { return }
        tearDown()
    }

    private func tearDown() {
        guard let output else { return }
        output.player.stop()
        output.engine.stop()
        self.output = nil
    }

    private func buffer(for key: SoundKey) -> AVAudioPCMBuffer? {
        if let buffer = buffers[key] {
            return buffer
        }
        let buffer = makeBuffer(SoundSynth.shiftSound(profile: key.profile, intensity: key.intensity))
        buffers[key] = buffer
        return buffer
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
