import Foundation
import MobiPadNetwork
import MobiPadProtocol
import MobiPadVideo
import Observation

/// The Wii U GamePad's picture for the touchscreen area, streamed from Cemu's GamePad window by the Mac,
/// while the GamePad layout is on screen.
@MainActor @Observable
final class GamePadScreen {
    let display = VideoDisplay()
    /// What the Mac last said about the stream. Nil until it answers, and with a Mac app from before video.
    private(set) var status: SessionMessage.VideoStatus?
    /// Whether a picture is showing. False until the first one is decoded.
    private(set) var hasPicture = false
    @ObservationIgnored private var player: VideoPlayer?
    @ObservationIgnored private let firstPicture = FirstPicture()

    /// Asks the Mac for the stream over `link`, and shows what arrives.
    func start(on link: ControllerLink) {
        reset()
        let display = display
        let firstPicture = firstPicture
        let player = VideoPlayer(
            onPicture: { [weak self] picture in
                display.show(picture)
                if firstPicture.take() {
                    Task { @MainActor in self?.hasPicture = true }
                }
            },
            requestKeyframe: { link.requestKeyframe() }
        )
        self.player = player
        link.receiveVideo { [weak self] event in
            switch event {
            // Straight to the player's queue: decoding never holds up the link, which sends the controls.
            case .fragment(let fragment): player.receive(fragment)
            case .status(let status): Task { @MainActor in self?.update(status) }
            }
        }
    }

    /// Stops asking for the stream.
    func stop(on link: ControllerLink?) {
        link?.receiveVideo(nil)
        reset()
    }

    private func update(_ newStatus: SessionMessage.VideoStatus) {
        guard newStatus != status else { return }
        status = newStatus
        if newStatus != .streaming {
            hasPicture = false
            firstPicture.reset()
            display.clear()
        }
    }

    private func reset() {
        player = nil
        status = nil
        hasPicture = false
        firstPicture.reset()
        display.clear()
    }
}

/// Lets the player's queue report only the first picture to the main actor, not every frame.
private final class FirstPicture: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var isWaiting = true

    /// True once, for the first picture after a reset.
    func take() -> Bool {
        lock.withLock {
            defer { isWaiting = false }
            return isWaiting
        }
    }

    func reset() {
        lock.withLock { isWaiting = true }
    }
}
