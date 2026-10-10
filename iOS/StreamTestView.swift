#if DEBUG
import AVFoundation
import CoreMedia
import MobiPadNetwork
import MobiPadVideo
import os
import SwiftUI

/// A development screen, in debug builds only: shows the video from the StreamProbe tool on the Mac,
/// which measures how long a picture takes to reach the phone. See tools/StreamProbe.
struct StreamTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var macs: [MacBrowser.Mac] = []
    @State private var browser: MacBrowser?
    @State private var session: StreamSession?

    static var opensAtLaunch: Bool { ProcessInfo.processInfo.arguments.contains("-streamTest") }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    StreamPlayer(session: session)
                        .ignoresSafeArea()
                        .overlay(alignment: .bottomLeading) {
                            Text(session.statusText)
                                .font(.caption.monospacedDigit())
                                .padding(8)
                                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                                .padding()
                        }
                } else {
                    List {
                        Section {
                            if macs.isEmpty {
                                ContentUnavailableView(
                                    "Looking for StreamProbe",
                                    systemImage: "video",
                                    description: Text("On the Mac, run: swift run -c release --package-path tools/StreamProbe StreamProbe")
                                )
                            }
                            ForEach(macs) { mac in
                                Button {
                                    session = StreamSession(endpoint: mac.endpoint)
                                } label: {
                                    Label(mac.name, systemImage: "desktopcomputer")
                                }
                            }
                        } footer: {
                            Text("Shows the Mac’s test stream. The Mac measures the delay and prints it.")
                        }
                    }
                }
            }
            .navigationTitle("Stream Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") {
                    session?.stop()
                    dismiss()
                }
            }
        }
        .onAppear {
            let browser = MacBrowser(type: ProbeMessage.bonjourType) { macs in
                MainActor.assumeIsolated {
                    self.macs = macs
                    // Launched with -streamTest: connect to the first Mac found, for testing in the Simulator.
                    if session == nil, Self.opensAtLaunch, let mac = macs.first {
                        session = StreamSession(endpoint: mac.endpoint)
                    }
                }
            }
            browser.start()
            self.browser = browser
        }
        .onDisappear {
            browser?.stop()
            session?.stop()
        }
    }
}

/// One connection to StreamProbe, and the layer that shows its pictures.
@Observable @MainActor
final class StreamSession {
    let layer = AVSampleBufferDisplayLayer()
    private(set) var status = ProbeClient.Status()
    private var client: ProbeClient?

    init(endpoint: NWEndpoint) {
        layer.videoGravity = .resizeAspect
        let renderer = Renderer(layer.sampleBufferRenderer)
        let client = ProbeClient(
            to: endpoint,
            onPicture: { picture in
                // Shown as soon as it's enqueued, without waiting for a presentation time.
                guard let sample = Self.sampleBuffer(for: picture) else {
                    Logger(subsystem: "MobiPad", category: "probe").error("Couldn't wrap a decoded picture for display")
                    return
                }
                renderer.value.enqueue(sample)
            },
            onStatus: { [weak self] status in
                Task { @MainActor in self?.status = status }
            }
        )
        client.start()
        self.client = client
    }

    var statusText: String {
        var text = "Decoded \(status.framesDecoded) · lost \(status.framesLost)"
        if let error = status.lastError {
            text += "\n\(error)"
        }
        return text
    }

    func stop() {
        client?.stop()
        client = nil
    }

    nonisolated private static func sampleBuffer(for picture: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: picture, formatDescriptionOut: &format) == noErr,
              let format
        else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: picture, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sample
    }
}

/// The renderer takes sample buffers from any thread (AVQueuedSampleBufferRendering), but isn't
/// marked Sendable.
private struct Renderer: @unchecked Sendable {
    let value: AVSampleBufferVideoRenderer
    init(_ value: AVSampleBufferVideoRenderer) { self.value = value }
}

private struct StreamPlayer: UIViewRepresentable {
    let session: StreamSession

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        view.layer.addSublayer(session.layer)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    final class PlayerView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.forEach { $0.frame = bounds }
        }
    }
}
#endif
