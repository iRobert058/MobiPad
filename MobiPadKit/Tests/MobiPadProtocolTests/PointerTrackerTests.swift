import Foundation
import Testing
import MobiPadProtocol

/// Motion is in the screen's axes (x to the right edge, y to the top, z out of the screen), as the
/// pointing Wii Remote layout sends it: the phone upright in the hand, screen up, top toward the TV.
struct PointerTrackerTests {
    typealias Motion = ControllerState.Motion

    /// Lying face up: gravity measured out of the screen.
    static let flat = Motion.Vector(x: 0, y: 0, z: 1)
    /// Tilted 45° with the top end up, as a remote aimed a bit upward is held.
    static let raised = Motion.Vector(x: 0, y: Float(0.5.squareRoot()), z: Float(0.5.squareRoot()))

    /// Turns at `degreesPerSecond` around the screen-frame axis `axis` for one second, in 100 steps.
    static func turn(_ tracker: inout PointerTracker, around axis: Motion.Vector, degreesPerSecond: Float, held: Motion.Vector = flat) {
        let rate = Motion.Vector(x: axis.x * degreesPerSecond, y: axis.y * degreesPerSecond, z: axis.z * degreesPerSecond)
        for _ in 0..<100 {
            tracker.update(Motion(acceleration: held, rotationRate: rate), seconds: 0.01)
        }
    }

    static func expect(_ tracker: PointerTracker, x: Double, y: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(tracker.position.x - x) < 0.01, "x is \(tracker.position.x), not \(x)", sourceLocation: sourceLocation)
        #expect(abs(tracker.position.y - y) < 0.01, "y is \(tracker.position.y), not \(y)", sourceLocation: sourceLocation)
    }

    @Test func startsInTheMiddle() {
        Self.expect(PointerTracker(), x: 0.5, y: 0.5)
    }

    /// Turning left is counterclockwise seen from above: positive around the screen's z when lying flat.
    @Test func turningLeftMovesThePointerLeft() {
        var tracker = PointerTracker()
        Self.turn(&tracker, around: .init(x: 0, y: 0, z: 1), degreesPerSecond: 5)
        Self.expect(tracker, x: 0.5 - 5 / PointerTracker.totalYaw, y: 0.5)
    }

    /// Lifting the top end is positive around the right edge.
    @Test func liftingTheTopEndMovesThePointerUp() {
        var tracker = PointerTracker()
        Self.turn(&tracker, around: .init(x: 1, y: 0, z: 0), degreesPerSecond: 3)
        Self.expect(tracker, x: 0.5, y: 0.5 - 3 / PointerTracker.totalPitch)
    }

    /// Held tilted up, turning left is around the room's vertical, which is between the screen's y and z.
    /// Turning around the screen's z alone would also roll the phone, and only part of it counts.
    @Test func followsTheRoomsVerticalWhenTilted() {
        var tracker = PointerTracker()
        let vertical = Self.raised
        // Let the smoothing settle on the tilted pose first.
        Self.turn(&tracker, around: vertical, degreesPerSecond: 0, held: Self.raised)
        Self.turn(&tracker, around: vertical, degreesPerSecond: 5, held: Self.raised)
        Self.expect(tracker, x: 0.5 - 5 / PointerTracker.totalYaw, y: 0.5)
    }

    /// The pointer stops at the edge, and comes back as soon as the phone turns back.
    @Test func staysOnScreenAndComesBackRightAway() {
        var tracker = PointerTracker()
        Self.turn(&tracker, around: .init(x: 0, y: 0, z: 1), degreesPerSecond: -90)
        Self.expect(tracker, x: 1, y: 0.5)
        Self.turn(&tracker, around: .init(x: 0, y: 0, z: 1), degreesPerSecond: 5)
        Self.expect(tracker, x: 1 - 5 / PointerTracker.totalYaw, y: 0.5)
    }

    @Test func recenterPutsItBackInTheMiddle() {
        var tracker = PointerTracker()
        Self.turn(&tracker, around: .init(x: 1, y: 0, z: 1), degreesPerSecond: 4)
        tracker.recenter()
        Self.expect(tracker, x: 0.5, y: 0.5)
    }

    /// A late reading (the app was paused) doesn't throw the pointer across the screen.
    @Test func ignoresLongGaps() {
        var tracker = PointerTracker()
        tracker.update(Motion(acceleration: Self.flat, rotationRate: .init(x: 0, y: 0, z: 10)), seconds: 5)
        Self.expect(tracker, x: 0.5 - 1 / PointerTracker.totalYaw, y: 0.5)
    }
}
