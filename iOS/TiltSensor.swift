import CoreMotion
import MobiPadProtocol
import Observation
import UIKit

/// Reads the phone's motion sensors for the Wii Remote layouts, 100 times a second, which keeps
/// Dolphin's pointer smooth.
///
/// Reading the accelerometer and gyroscope this way needs no permission from the user.
@MainActor @Observable
final class TiltSensor {
    /// The latest reading, for the steering indicator. Nil while stopped.
    private(set) var motion: ControllerState.Motion?

    /// Apple recommends one motion manager per app, and SwiftUI may create spare sensors.
    private static let manager = CMMotionManager()
    private var manager: CMMotionManager { Self.manager }
    @ObservationIgnored private var onUpdate: (@MainActor (ControllerState.Motion?) -> Void)?

    /// False in the Simulator and on devices without a gyroscope.
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Calls `onUpdate` with every reading, and with nil once stopped.
    func start(onUpdate: @escaping @MainActor (ControllerState.Motion?) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        // Takes over the shared manager, in case an earlier sensor left it running.
        manager.stopDeviceMotionUpdates()
        self.onUpdate = onUpdate
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let gravity = ControllerState.Motion.Vector(data.gravity)
            let userAcceleration = ControllerState.Motion.Vector(data.userAcceleration)
            let rotationRate = ControllerState.Motion.Vector(data.rotationRate)
            // Updates arrive on the main queue.
            MainActor.assumeIsolated {
                self?.update(gravity: gravity, userAcceleration: userAcceleration, rotationRate: rotationRate)
            }
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        motion = nil
        onUpdate?(nil)
        onUpdate = nil
    }

    private func update(
        gravity: ControllerState.Motion.Vector,
        userAcceleration: ControllerState.Motion.Vector,
        rotationRate: ControllerState.Motion.Vector
    ) {
        let motion = ControllerState.Motion(
            gravity: gravity,
            userAcceleration: userAcceleration,
            rotationRate: rotationRate,
            orientation: orientation
        )
        self.motion = motion
        onUpdate?(motion)
    }

    /// Which way round the screen is, which decides where the phone's left and right are.
    private var orientation: ControllerState.Motion.Orientation {
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
        return switch scene?.effectiveGeometry.interfaceOrientation {
        case .portrait: .portrait
        // UIKit's landscapeLeft has the top of the phone on the right.
        case .landscapeLeft: .topOnRight
        default: .topOnLeft
        }
    }
}

private extension ControllerState.Motion.Vector {
    init(_ acceleration: CMAcceleration) {
        self.init(x: Float(acceleration.x), y: Float(acceleration.y), z: Float(acceleration.z))
    }

    init(_ rotationRate: CMRotationRate) {
        self.init(x: Float(rotationRate.x), y: Float(rotationRate.y), z: Float(rotationRate.z))
    }
}
