import Foundation
import MobiPadNetwork
import MobiPadProtocol
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Finds Macs, and owns the link to the one the user picked.
@MainActor @Observable
final class AppModel {
    private(set) var macs: [MacBrowser.Mac] = []
    private(set) var connectedMac: MacBrowser.Mac?
    private(set) var status = ControllerLink.Status.disconnected

    private var browser: MacBrowser?
    private var link: ControllerLink?
    /// Ignores status updates from a link that has since been replaced.
    private var linkToken = UUID()

    var statusText: String {
        let macName = connectedMac?.name ?? "Mac"
        return switch status {
        case .connecting: "Connecting to \(macName)…"
        case .connected(let slot): "Player \(slot + 1)"
        case .full: "\(macName) already has 4 players"
        case .disconnected: "Disconnected"
        }
    }

    func startBrowsing() {
        guard browser == nil else { return }
        // Called on the main queue.
        let browser = MacBrowser { [weak self] macs in
            MainActor.assumeIsolated { self?.macs = macs }
        }
        browser.start()
        self.browser = browser
    }

    func connect(to mac: MacBrowser.Mac) {
        browser?.stop()
        browser = nil
        link?.disconnect()

        let token = UUID()
        linkToken = token
        let link = ControllerLink(to: mac.endpoint, clientID: Self.clientID, name: Self.deviceName) { [weak self] status in
            Task { @MainActor in
                guard let self, self.linkToken == token else { return }
                self.status = status
            }
        }
        self.link = link
        connectedMac = mac
        link.connect()
    }

    func disconnect() {
        link?.disconnect()
        link = nil
        linkToken = UUID()
        connectedMac = nil
        status = .disconnected
    }

    func send(_ state: ControllerState) {
        link?.send(state)
    }

    /// Stays the same across launches, so the Mac gives this phone its player number back.
    private static let clientID: UUID = {
        let key = "clientID"
        if let stored = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }()

    private static var deviceName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}
