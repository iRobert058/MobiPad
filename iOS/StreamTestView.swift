#if DEBUG
import MobiPadNetwork
import MobiPadVideo
import Network
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
                    VideoDisplayView(display: session.display)
                        .background(.black)
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

/// One connection to StreamProbe, and the display that shows its pictures.
@Observable @MainActor
final class StreamSession {
    let display = VideoDisplay()
    private(set) var status = ProbeClient.Status()
    private var client: ProbeClient?

    init(endpoint: NWEndpoint) {
        let display = display
        let client = ProbeClient(
            to: endpoint,
            onPicture: { picture in display.show(picture) },
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
}
#endif
