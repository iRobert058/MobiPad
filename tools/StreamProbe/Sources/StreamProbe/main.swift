import AppKit
import CoreMedia
import Foundation
import MobiPadVideo
import Network
import ScreenCaptureKit

// Streams video to the phone's Stream Test screen (debug builds of the iPhone app) and measures the
// delay as a loop on the Mac's clock: the marker in the picture switches between black and white,
// the phone reports the first decoded frame that shows the switch, and the time until that report
// arrives is one sample. It covers capture (window source), encoding, Wi-Fi both ways and decoding;
// not the phone's display, which adds up to one refresh.

let usage = """
    Usage: StreamProbe [--source pattern|window] [--capture <window title>] [--fps 60] [--mbps 6] [--samples 300] [--port 0]

      --source pattern   A generated test picture (default). No permission needed.
      --source window    A window of its own, captured like Cemu's would be. Needs Screen Recording
                         permission for the app this runs in (System Settings → Privacy & Security).
      --capture <title>  Streams another window whose title contains <title>, such as Cemu's
                         "GamePad View", to see how it feels. No measurement. Needs Screen Recording.
      --fps, --mbps      Frame rate and bit rate. --samples: stop after this many measurements.
      --phone <host:port>  Instead of streaming, act as the phone: receive from a StreamProbe at that
                         address, for testing the loop on one Mac.
    """

struct Options {
    enum Source: Equatable {
        case pattern
        case window
        case capture(String)
    }

    /// Set when this process acts as the phone.
    var phone: (host: String, port: UInt16)?

    var source = Source.pattern
    var framesPerSecond = 60.0
    var megabitsPerSecond = 6.0
    var samples = 300
    var port: UInt16 = 0

    init(_ arguments: [String]) throws {
        var arguments = arguments[...]
        func value(_ flag: String) throws -> String {
            guard let value = arguments.popFirst() else { throw UsageError(message: "\(flag) needs a value") }
            return value
        }
        while let flag = arguments.popFirst() {
            switch flag {
            case "--source":
                switch try value(flag) {
                case "pattern": source = .pattern
                case "window": source = .window
                case let other: throw UsageError(message: "unknown source \(other)")
                }
            case "--capture": source = .capture(try value(flag))
            case "--fps": framesPerSecond = try number(value(flag), flag)
            case "--mbps": megabitsPerSecond = try number(value(flag), flag)
            case "--samples": samples = Int(try number(value(flag), flag))
            case "--port": port = UInt16(try number(value(flag), flag))
            case "--phone":
                let address = try value(flag)
                guard let colon = address.lastIndex(of: ":"), let port = UInt16(address[address.index(after: colon)...]) else {
                    throw UsageError(message: "--phone needs host:port")
                }
                phone = (String(address[..<colon]), port)
            case "--help", "-h": throw UsageError(message: nil)
            default: throw UsageError(message: "unknown option \(flag)")
            }
        }
    }

    private func number(_ text: String, _ flag: String) throws -> Double {
        guard let number = Double(text), number > 0 else { throw UsageError(message: "\(flag) needs a positive number") }
        return number
    }
}

struct UsageError: Error {
    let message: String?
}

/// Sends the encoded frames to the phone that subscribed last, and keeps the statistics.
final class Streamer: @unchecked Sendable {
    let queue = DispatchQueue(label: "StreamProbe")
    private let options: Options
    private var listener: NWListener?
    private var phone: NWConnection?
    private var lastSubscribe = ContinuousClock.now
    private var encoder: VideoEncoder!
    private var frameNumber: UInt32 = 0
    private var wantsKeyframe = true
    private var lastKeyframeRequest = ContinuousClock.now - .seconds(1)
    private var started = ContinuousClock.now
    private var submitted: [CMTimeValue: ContinuousClock.Instant] = [:]
    private var inputFrames: Int64 = 0

    /// Called on the queue when the phone reports seeing the marker switch.
    var onSeen: ((Bool) -> Void)?

    struct Stats {
        var frames = 0
        var keyframes = 0
        var bytes = 0
        var keyframeBytes = 0
        var maxFragments = 0
        var encodeMilliseconds: [Double] = []
        var keyframeRequests = 0
        var encoderErrors = 0
        var phone: ProbeMessage.PhoneStats?
    }
    private(set) var stats = Stats()

    init(options: Options) throws {
        self.options = options
        var settings = VideoEncoder.Settings()
        settings.framesPerSecond = options.framesPerSecond
        settings.bitsPerSecond = Int(options.megabitsPerSecond * 1_000_000)
        encoder = try VideoEncoder(settings: settings) { [weak self] time, result in
            guard let self else { return }
            queue.async { self.send(time: time, result) }
        }
    }

    var isStreaming: Bool {
        phone != nil && ContinuousClock.now - lastSubscribe < .seconds(3)
    }

    func start() throws {
        let parameters = NWParameters.udp
        let listener = try NWListener(using: parameters, on: options.port == 0 ? .any : NWEndpoint.Port(rawValue: options.port)!)
        listener.service = NWListener.Service(name: Host.current().localizedName, type: ProbeMessage.bonjourType)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: print("Listening on port \(listener.port?.rawValue ?? 0), advertised as \(ProbeMessage.bonjourType). Open Stream Test on the phone.")
            case .failed(let error):
                print("Listener failed: \(error)")
                exit(1)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Encodes a picture for the phone. On the queue.
    func submit(_ pixelBuffer: CVPixelBuffer) {
        guard isStreaming else { return }
        inputFrames += 1
        let time = CMTime(value: inputFrames, timescale: CMTimeScale(options.framesPerSecond.rounded()))
        submitted[inputFrames] = .now
        let forceKeyframe = wantsKeyframe
        wantsKeyframe = false
        do {
            try encoder.encode(pixelBuffer, time: time, forceKeyframe: forceKeyframe)
        } catch {
            stats.encoderErrors += 1
            print("Encoder error: \(error)")
        }
    }

    private func send(time: CMTime, _ result: Result<EncodedFrame, VideoEncoder.EncoderError>) {
        if let start = submitted.removeValue(forKey: time.value) {
            stats.encodeMilliseconds.append((ContinuousClock.now - start).milliseconds)
        }
        let frame: EncodedFrame
        switch result {
        case .success(let encoded): frame = encoded
        case .failure(let error):
            stats.encoderErrors += 1
            print("Encoder error: \(error)")
            return
        }
        guard let phone else { return }
        let data = frame.encoded()
        frameNumber &+= 1
        guard let fragments = VideoFragment.split(data, frame: frameNumber) else {
            print("Dropped a frame of \(data.count) bytes: too large")
            return
        }
        for fragment in fragments {
            phone.send(content: ProbeMessage.fragment(fragment).encoded(), completion: .idempotent)
        }
        stats.frames += 1
        stats.bytes += data.count
        stats.maxFragments = max(stats.maxFragments, fragments.count)
        if frame.isKeyframe {
            stats.keyframes += 1
            stats.keyframeBytes += data.count
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil else { return }
            if let data {
                handle(data, from: connection)
            }
            receive(on: connection)
        }
    }

    private func handle(_ data: Data, from connection: NWConnection) {
        guard let message = try? ProbeMessage(decoding: data) else {
            print("Dropped a datagram that isn't a probe message")
            return
        }
        switch message {
        case .subscribe:
            if phone !== connection {
                phone?.cancel()
                phone = connection
                wantsKeyframe = true
                started = .now
                print("Streaming to \(connection.endpoint)")
            }
            lastSubscribe = .now
        case .keyframe:
            guard phone === connection, ContinuousClock.now - lastKeyframeRequest > .milliseconds(100) else { return }
            lastKeyframeRequest = .now
            wantsKeyframe = true
            stats.keyframeRequests += 1
        case .seen(let white):
            guard phone === connection else { return }
            onSeen?(white)
        case .stats(let phoneStats):
            stats.phone = phoneStats
        case .fragment:
            break
        }
    }

    var elapsedSeconds: Double { (ContinuousClock.now - started).seconds }
}

/// Switches the marker at random intervals and times how long the phone takes to see each switch.
/// Used only on the streamer's queue.
final class LatencyMeter: @unchecked Sendable {
    private(set) var markerWhite = false
    private var switchedAt: ContinuousClock.Instant?
    private var nextSwitch = ContinuousClock.now + .seconds(1)
    private(set) var samples: [Double] = []
    private(set) var missed = 0

    /// Whether the marker should switch now: half a second or so after the last one was seen.
    /// A random interval, so the switches don't line up with the frame timing.
    func shouldSwitch(at now: ContinuousClock.Instant) -> Bool {
        if let switchedAt, now - switchedAt > .seconds(1) {
            // Never seen: lost, or the phone isn't decoding.
            missed += 1
            self.switchedAt = nil
            nextSwitch = now
        }
        return switchedAt == nil && now >= nextSwitch
    }

    /// Call when the switched marker becomes visible: drawn into a picture, or on screen.
    func switched(at now: ContinuousClock.Instant) {
        markerWhite.toggle()
        switchedAt = now
    }

    func seen(white: Bool) {
        guard white == markerWhite, let switchedAt else { return }
        let now = ContinuousClock.now
        samples.append((now - switchedAt).milliseconds)
        self.switchedAt = nil
        nextSwitch = now + .milliseconds(Int.random(in: 300...600))
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
    var milliseconds: Double { seconds * 1_000 }
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return .nan }
    return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
}

func format(_ value: Double) -> String { String(format: "%.1f", value) }

func report(_ streamer: Streamer, _ meter: LatencyMeter?, final: Bool) {
    let stats = streamer.stats
    let seconds = max(streamer.elapsedSeconds, 0.001)
    var lines: [String] = []
    if let meter {
        let samples = meter.samples
        if samples.isEmpty {
            lines.append("Loop delay: no samples yet (missed \(meter.missed))")
        } else {
            lines.append("Loop delay (ms), \(samples.count) samples: median \(format(percentile(samples, 0.5))), p90 \(format(percentile(samples, 0.9))), p99 \(format(percentile(samples, 0.99))), min \(format(samples.min()!)), max \(format(samples.max()!)); missed \(meter.missed)")
        }
    }
    let encode = stats.encodeMilliseconds
    if !encode.isEmpty {
        lines.append("Encode (ms): median \(format(percentile(encode, 0.5))), p90 \(format(percentile(encode, 0.9))), max \(format(encode.max()!))")
    }
    let deltaFrames = max(stats.frames - stats.keyframes, 1)
    lines.append("Sent \(stats.frames) frames (\(format(Double(stats.frames) / seconds)) fps), \(format(Double(stats.bytes) * 8 / seconds / 1e6)) Mbit/s, keyframes \(stats.keyframes) (mean \(stats.keyframes == 0 ? 0 : stats.keyframeBytes / stats.keyframes) B), other frames mean \((stats.bytes - stats.keyframeBytes) / deltaFrames) B, max \(stats.maxFragments) datagrams per frame; keyframes asked \(stats.keyframeRequests)")
    if let phone = stats.phone {
        lines.append("Phone: completed \(phone.completed), lost \(phone.lost), decoded \(phone.decoded), decode mean \(format(Double(phone.meanDecodeMicroseconds) / 1_000)) ms")
    }
    print((final ? "\n=== Result ===\n" : "") + lines.joined(separator: "\n") + (final ? "" : "\n"))
}

// MARK: - Sources

/// The generated picture, made and encoded on the streamer's queue at the frame rate.
func runPattern(_ streamer: Streamer, _ meter: LatencyMeter, options: Options) throws -> DispatchSourceTimer {
    let pattern = try TestPattern()
    var number = 0
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: streamer.queue)
    timer.schedule(deadline: .now(), repeating: 1 / options.framesPerSecond, leeway: .milliseconds(1))
    timer.setEventHandler {
        guard streamer.isStreaming else { return }
        let now = ContinuousClock.now
        if meter.shouldSwitch(at: now) {
            meter.switched(at: now)
        }
        number += 1
        do {
            streamer.submit(try pattern.frame(number, markerWhite: meter.markerWhite))
        } catch {
            print("Couldn't make a test picture: \(error)")
        }
    }
    timer.resume()
    return timer
}

/// A borderless window showing the moving stripes and the marker, captured by ScreenCaptureKit.
final class MarkerView: NSView {
    var markerWhite = false
    var number = 0

    override func draw(_ dirtyRect: NSRect) {
        NSColor.darkGray.setFill()
        bounds.fill()
        NSColor.gray.setFill()
        for stripe in stride(from: -Int(bounds.height), to: Int(bounds.width), by: 32) {
            let x = CGFloat(stripe + number * 4 % 32)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x + 16, y: 0))
            path.line(to: NSPoint(x: x + 16 + bounds.height, y: bounds.height))
            path.line(to: NSPoint(x: x + bounds.height, y: bounds.height))
            path.fill()
        }
        // Top-left, where the phone looks. AppKit's y axis points up.
        let side = min(bounds.width, bounds.height) * LatencyMarker.size
        (markerWhite ? NSColor.white : NSColor.black).setFill()
        NSRect(x: 0, y: bounds.height - side, width: side, height: side).fill()
    }
}

final class FrameOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let streamer: Streamer
    init(streamer: Streamer) { self.streamer = streamer }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let rawStatus = info[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        streamer.submit(pixelBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("Capture stopped: \(error.localizedDescription)")
        exit(1)
    }
}

@MainActor
func startCapture(of window: SCWindow, streamer: Streamer, options: Options) async throws -> (SCStream, FrameOutput) {
    let configuration = SCStreamConfiguration()
    configuration.width = 854
    configuration.height = 480
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.framesPerSecond.rounded()))
    configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    configuration.showsCursor = false
    configuration.queueDepth = 3
    let output = FrameOutput(streamer: streamer)
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: output)
    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: streamer.queue)
    try await stream.startCapture()
    return (stream, output)
}

@MainActor
func findWindow(_ match: (SCWindow) -> Bool) async throws -> SCWindow {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
        throw UsageError(message: "No Screen Recording permission. Allow it for this terminal app in System Settings → Privacy & Security → Screen & System Audio Recording, restart the terminal, and run again.")
    }
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: match) else {
        let titles = content.windows.compactMap(\.title).filter { !$0.isEmpty }
        throw UsageError(message: "No such window. Windows on screen: \(titles.joined(separator: ", "))")
    }
    return window
}

// MARK: - Main

let options: Options
do {
    options = try Options(Array(CommandLine.arguments.dropFirst()))
} catch let error as UsageError {
    if let message = error.message { print("Error: \(message)\n") }
    print(usage)
    exit(error.message == nil ? 0 : 2)
}

if let phone = options.phone {
    let client = ProbeClient(
        to: .hostPort(host: NWEndpoint.Host(phone.host), port: NWEndpoint.Port(rawValue: phone.port)!),
        onPicture: { _ in },
        onStatus: { status in
            print("Phone: decoded \(status.framesDecoded), lost \(status.framesLost)\(status.lastError.map { ", error: \($0)" } ?? "")")
        }
    )
    client.start()
    withExtendedLifetime(client) { dispatchMain() }
}

/// Streams to the phone. Not on the main actor: the timers' handlers run on the streamer's queue.
nonisolated func stream(options: Options) throws -> Never {
    let streamer = try Streamer(options: options)
    let meter: LatencyMeter? = if case .capture = options.source { nil } else { LatencyMeter() }
    streamer.queue.sync { streamer.onSeen = { meter?.seen(white: $0) } }
    try streamer.start()

    let reportTimer = DispatchSource.makeTimerSource(queue: streamer.queue)
    reportTimer.schedule(deadline: .now() + 5, repeating: 5)
    reportTimer.setEventHandler { @Sendable in
        guard streamer.isStreaming else { return }
        report(streamer, meter, final: false)
        if let meter, meter.samples.count >= options.samples {
            report(streamer, meter, final: true)
            exit(0)
        }
    }
    reportTimer.resume()

    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: streamer.queue)
    interrupt.setEventHandler { @Sendable in
        report(streamer, meter, final: true)
        exit(0)
    }
    interrupt.resume()

    switch options.source {
    case .pattern:
        let timer = try runPattern(streamer, meter!, options: options)
        withExtendedLifetime(timer) { dispatchMain() }

    case .window, .capture:
        // Called on the main thread, from the top level.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            var keep: [AnyObject] = []
            Task { @MainActor in
                do {
                    if case .capture(let title) = options.source {
                        let window = try await findWindow { $0.title?.localizedCaseInsensitiveContains(title) == true }
                        print("Capturing “\(window.title ?? "")”")
                        let (stream, output) = try await startCapture(of: window, streamer: streamer, options: options)
                        keep += [stream, output]
                        return
                    }

                    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 854, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
                    let view = MarkerView()
                    window.contentView = view
                    window.level = .floating
                    window.orderFrontRegardless()
                    keep.append(window)

                    let ownWindow = try await findWindow { $0.windowID == CGWindowID(window.windowNumber) }
                    let (stream, output) = try await startCapture(of: ownWindow, streamer: streamer, options: options)
                    keep += [stream, output]

                    // Animates the stripes and switches the marker; the switch is timed once it's drawn.
                    let meter = meter!
                    let timer = Timer(timeInterval: 1 / options.framesPerSecond, repeats: true) { _ in
                        MainActor.assumeIsolated {
                            view.number += 1
                            let shouldSwitch = streamer.queue.sync { streamer.isStreaming && meter.shouldSwitch(at: .now) }
                            if shouldSwitch {
                                view.markerWhite.toggle()
                            }
                            view.display()
                            if shouldSwitch {
                                // Drawn into the window's buffer; the window server shows it at the next refresh.
                                streamer.queue.sync { meter.switched(at: .now) }
                            }
                        }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    keep.append(timer)
                } catch let error as UsageError {
                    print("Error: \(error.message ?? "")")
                    exit(1)
                } catch {
                    print("Error: \(error.localizedDescription)")
                    exit(1)
                }
            }
            app.run()
        }
    }
    exit(0)
}

try stream(options: options)
