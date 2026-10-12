import CoreVideo
import Foundation
import MobiPadProtocol
import Testing
@testable import MobiPadVideo

/// The streamer with a pretend window that shows the test pattern at 60 frames a second.
@Suite(.timeLimit(.minutes(1)))
struct GamePadStreamerTests {
    /// Plays Cemu's GamePad window: `result` decides whether starting works.
    final class FakeSource: FrameSource, @unchecked Sendable {
        private let lock = NSLock()
        private var _result: SessionMessage.VideoStatus
        private var timer: DispatchSourceTimer?
        private var onStop: (@Sendable () -> Void)?
        private(set) var starts = 0
        private(set) var stops = 0
        /// Sends the same picture over and over when set, like a still screen sends none at all.
        var isStill = false

        init(result: SessionMessage.VideoStatus = .streaming) {
            _result = result
        }

        var result: SessionMessage.VideoStatus {
            get { lock.withLock { _result } }
            set { lock.withLock { _result = newValue } }
        }

        var isRunning: Bool { lock.withLock { timer != nil } }

        func start(
            onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
            onStop: @escaping @Sendable () -> Void
        ) async -> SessionMessage.VideoStatus {
            lock.withLock {
                starts += 1
                guard _result == .streaming else { return _result }
                let pattern = try! TestPattern()
                var number = 0
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now(), repeating: 1.0 / 60)
                timer.setEventHandler { [weak self] in
                    guard let self, !lock.withLock({ isStill }) || number == 0 else { return }
                    number += 1
                    onFrame(try! pattern.frame(number, markerWhite: false))
                }
                timer.resume()
                self.timer = timer
                self.onStop = onStop
                return .streaming
            }
        }

        func stop() async {
            lock.withLock {
                stops += 1
                timer?.cancel()
                timer = nil
            }
        }

        /// The window closes.
        func close() {
            let onStop = lock.withLock {
                timer?.cancel()
                timer = nil
                return self.onStop
            }
            onStop?()
        }
    }

    /// What the streamer sent: fragments per slot, and statuses per slot.
    final class Outbox: @unchecked Sendable {
        private let lock = NSLock()
        private var fragments: [Int: [Data]] = [:]
        private var statuses: [Int: [SessionMessage.VideoStatus]] = [:]

        func send(_ fragment: Data, to slots: Set<Int>) {
            lock.withLock { for slot in slots { fragments[slot, default: []].append(fragment) } }
        }

        func send(_ status: SessionMessage.VideoStatus, to slot: Int) {
            lock.withLock { statuses[slot, default: []].append(status) }
        }

        func fragments(_ slot: Int) -> [Data] { lock.withLock { fragments[slot] ?? [] } }
        func statuses(_ slot: Int) -> [SessionMessage.VideoStatus] { lock.withLock { statuses[slot] ?? [] } }
    }

    static var fastTiming: GamePadStreamer.Timing {
        var timing = GamePadStreamer.Timing()
        timing.requestTimeout = .milliseconds(400)
        timing.retryInterval = .milliseconds(200)
        timing.refreshInterval = .milliseconds(200)
        timing.tickInterval = .milliseconds(20)
        return timing
    }

    static func makeStreamer(_ source: FakeSource, _ outbox: Outbox) -> GamePadStreamer {
        GamePadStreamer(
            source: source,
            timing: fastTiming,
            send: { outbox.send($0, to: $1) },
            sendStatus: { outbox.send($0, to: $1) }
        )
    }

    static func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    struct TimedOut: Error {}

    /// Decodes everything a slot got, the way the phone does.
    static func decodedFrames(_ fragments: [Data]) throws -> Int {
        var receiver = VideoReceiver()
        let decoder = VideoDecoder()
        var count = 0
        for data in fragments {
            if let frame = receiver.receive(try VideoFragment(decoding: data)).frame {
                _ = try decoder.decode(frame)
                count += 1
            }
        }
        return count
    }

    @Test func offUntilThePlayerTurnsItOn() async throws {
        let source = FakeSource()
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.request(slot: 0, keyframe: true)
        try await Self.waitUntil { outbox.statuses(0) == [.off] }
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.starts == 0)
        #expect(outbox.fragments(0).isEmpty)
    }

    @Test func streamsToThePhoneThatAsks() async throws {
        let source = FakeSource()
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        streamer.request(slot: 1, keyframe: true)
        try await Self.waitUntil { outbox.fragments(1).count > 30 }
        #expect(outbox.fragments(0).isEmpty)
        #expect(outbox.statuses(1).last == .streaming)
        // Starts with a keyframe, so everything decodes.
        #expect(try Self.decodedFrames(outbox.fragments(1)) > 5)
    }

    @Test func stopsCapturingWhenNobodyAsks() async throws {
        let source = FakeSource()
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        streamer.request(slot: 0, keyframe: false)
        try await Self.waitUntil { source.isRunning }
        // No more requests: after the timeout, capture stops.
        try await Self.waitUntil { !source.isRunning }
        #expect(source.stops == 1)
    }

    @Test func turningItOffStopsCapture() async throws {
        let source = FakeSource()
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        streamer.request(slot: 0, keyframe: false)
        try await Self.waitUntil { source.isRunning }
        streamer.setEnabled(false)
        try await Self.waitUntil { !source.isRunning }
        streamer.request(slot: 0, keyframe: false)
        try await Self.waitUntil { outbox.statuses(0).last == .off }
    }

    /// Without Cemu's GamePad window, the phone hears why, and the streamer keeps looking for it.
    @Test func tellsThePhoneWhatsMissingAndTriesAgain() async throws {
        let source = FakeSource(result: .noWindow)
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        streamer.request(slot: 0, keyframe: false)
        try await Self.waitUntil { outbox.statuses(0).contains(.noWindow) }

        source.result = .streaming
        // The phone keeps asking, once a second in the app.
        for _ in 0..<10 where !source.isRunning {
            streamer.request(slot: 0, keyframe: false)
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Self.waitUntil { outbox.statuses(0).last == .streaming }
        #expect(source.starts >= 2)
    }

    @Test func noPermissionIsPassedOn() async throws {
        let source = FakeSource(result: .noPermission)
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        streamer.request(slot: 2, keyframe: false)
        try await Self.waitUntil { outbox.statuses(2).contains(.noPermission) }
    }

    @Test func windowClosingIsPassedOn() async throws {
        let source = FakeSource()
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        streamer.request(slot: 0, keyframe: false)
        try await Self.waitUntil { source.isRunning }
        source.close()
        try await Self.waitUntil { outbox.statuses(0).last == .noWindow }
    }

    /// A still screen sends no pictures, but the last one goes out again, and as a keyframe on request.
    @Test func resendsAStillPicture() async throws {
        let source = FakeSource()
        source.isStill = true
        let outbox = Outbox()
        let streamer = Self.makeStreamer(source, outbox)
        streamer.setEnabled(true)
        // The phone keeps asking, as the app does once a second.
        let asking = Task {
            while !Task.isCancelled {
                streamer.request(slot: 0, keyframe: false)
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { asking.cancel() }
        try await Self.waitUntil { !outbox.fragments(0).isEmpty }
        // The refresh, every 200 ms here.
        try await Self.waitUntil { Set(outbox.fragments(0).compactMap { try? VideoFragment(decoding: $0).frame }).count >= 3 }

        // A phone that joins now gets a keyframe at once.
        streamer.request(slot: 1, keyframe: true)
        try await Self.waitUntil { (try? Self.decodedFrames(outbox.fragments(1))) ?? 0 >= 1 }
    }
}
