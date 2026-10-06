import CoreHaptics
import os

/// Plays the game's rumble on the phone's Taptic Engine, the way a Wii Remote's motor buzzes when a
/// game rumbles it (FR-05).
///
/// The rumble comes from the emulator through the Mac (`ControllerLink`). A Wii Remote's motor is
/// either on or off, so emulators mostly send full strength or nothing; anything in between plays
/// softer. One buzz lasts as long as the rumble does, rather than separate taps, so it feels like a
/// spinning motor. The motor works on its own queue, so the link can call it straight from its own.
final class RumbleMotor: @unchecked Sendable {
    private let log = Logger(subsystem: "MobiPad", category: "rumble")
    private let queue = DispatchQueue(label: "MobiPad.RumbleMotor")
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var isPlaying = false
    private var intensity: UInt8 = 0

    /// Low sharpness feels like a motor spinning rather than a click.
    private static let sharpness: Float = 0.3

    /// Starts, changes or, with 0, stops the rumble.
    func set(_ intensity: UInt8) {
        queue.async { [self] in
            self.intensity = intensity
            apply()
        }
    }

    // MARK: - On queue

    private func apply() {
        guard intensity > 0 else {
            if isPlaying {
                try? player?.stop(atTime: CHHapticTimeImmediate)
                isPlaying = false
            }
            return
        }
        do {
            guard let player = try player ?? makePlayer() else { return }
            if !isPlaying {
                // The engine shuts down while nothing plays, to save battery.
                try engine?.start()
                try player.start(atTime: CHHapticTimeImmediate)
                isPlaying = true
            }
            try player.sendParameters(
                [CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(intensity) / 255, relativeTime: 0)],
                atTime: CHHapticTimeImmediate
            )
        } catch {
            log.error("Couldn't rumble: \(error, privacy: .public)")
        }
    }

    /// Nil in the Simulator and on phones without haptics.
    private func makePlayer() throws -> CHHapticAdvancedPatternPlayer? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine = try self.engine ?? makeEngine()
        let buzz = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.sharpness),
            ],
            relativeTime: 0,
            // The longest a continuous event can last. The player loops it.
            duration: 30
        )
        let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [buzz], parameters: []))
        player.loopEnabled = true
        self.player = player
        return player
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        // The system stops the engine when the app goes to the background, and after an error it
        // resets it, which throws its players away.
        engine.stoppedHandler = { [weak self] _ in
            guard let self else { return }
            queue.async { self.isPlaying = false }
        }
        engine.resetHandler = { [weak self] in
            guard let self else { return }
            queue.async {
                self.player = nil
                self.isPlaying = false
                self.apply()
            }
        }
        self.engine = engine
        return engine
    }
}
