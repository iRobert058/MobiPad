import Foundation

/// Where a phone held like a Wii Remote points on the TV, worked out from its gyroscope.
///
/// Dolphin works out the pointer itself from the motion, but Cemu takes it as a position, from the DSU
/// touch point. So for Cemu the phone turns its motion into that position: turning left moves the pointer
/// left and lifting the top end moves it up, measured around the room's vertical and horizontal axes, so
/// it doesn't matter how far the phone is tilted. Like Dolphin's Point, it drifts slowly over time;
/// ``recenter()`` puts it back in the middle, aimed wherever the phone points then.
public struct PointerTracker: Sendable {
    /// How far the phone turns to cross the whole screen, left to right: Dolphin's default "Total Yaw".
    public static let totalYaw: Double = 25
    /// Top to bottom, for a 16:9 TV, so the pointer moves as fast up and down as sideways.
    public static let totalPitch: Double = totalYaw * 9 / 16

    /// Degrees turned left of the center, and lifted above it, each kept within the screen's edges.
    private var yaw: Double = 0
    private var pitch: Double = 0
    /// Smoothed acceleration, which points away from the ground while the phone is held fairly still.
    private var up: SIMD3<Double>?

    public init() {}

    /// Follows one motion reading, taken `seconds` after the one before.
    public mutating func update(_ motion: ControllerState.Motion, seconds: Double) {
        let acceleration = SIMD3(Double(motion.acceleration.x), Double(motion.acceleration.y), Double(motion.acceleration.z))
        // Slow enough to ignore a flick of the wrist, fast enough to follow the phone being tilted.
        let smoothed = up.map { $0 + (acceleration - $0) * 0.1 } ?? acceleration
        up = smoothed
        let length = (smoothed * smoothed).sum().squareRoot()
        // Without gravity to go by (a hard shake, free fall), the screen's own axes are the best guess.
        let vertical = length > 0.3 ? smoothed / length : SIMD3(0, 0, 1)
        // The phone's right edge, levelled: the axis that lifting the top end turns around.
        let rightEdge = SIMD3<Double>(1, 0, 0)
        var horizontal = rightEdge - vertical * (rightEdge * vertical).sum()
        let horizontalLength = (horizontal * horizontal).sum().squareRoot()
        horizontal = horizontalLength > 0.1 ? horizontal / horizontalLength : rightEdge

        let rotation = SIMD3(Double(motion.rotationRate.x), Double(motion.rotationRate.y), Double(motion.rotationRate.z))
        let time = min(max(seconds, 0), 0.1)
        // Right-hand rule: turning counterclockwise seen from above (to the left) is positive around the
        // vertical, and lifting the top end is positive around the right edge.
        yaw = (yaw + (rotation * vertical).sum() * time).clamped(to: -Self.totalYaw / 2...Self.totalYaw / 2)
        pitch = (pitch + (rotation * horizontal).sum() * time).clamped(to: -Self.totalPitch / 2...Self.totalPitch / 2)
    }

    /// Puts the pointer in the middle of the screen.
    public mutating func recenter() {
        yaw = 0
        pitch = 0
    }

    /// The pointer as fractions of the screen from its top-left corner.
    public var position: (x: Double, y: Double) {
        (0.5 - yaw / Self.totalYaw, 0.5 - pitch / Self.totalPitch)
    }
}
