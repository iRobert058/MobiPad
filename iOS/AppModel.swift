import Foundation
import MobiPadNetwork
import MobiPadProtocol
import Observation

/// Finds Macs, and owns the link to the one the user picked.
@MainActor @Observable
final class AppModel {
    private(set) var macs: [MacBrowser.Mac] = []
    private(set) var connectedMac: MacBrowser.Mac?
    private(set) var status = ControllerLink.Status.disconnected

    /// Shown on the Mac, in the approval prompt and the player list.
    var playerName: String {
        didSet { UserDefaults.standard.set(playerName, forKey: Self.playerNameKey) }
    }

    /// Where the controls sit on the controller screen (UX-03).
    var layout: ControllerLayout {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(layout), forKey: Self.layoutKey) }
    }

    private var browser: MacBrowser?
    private var link: ControllerLink?
    /// Ignores status updates from a link that has since been replaced.
    private var linkToken = UUID()

    private static let playerNameKey = "playerName"
    private static let layoutKey = "controllerLayout"
    private static let identityKey = "identityKey"

    init() {
        playerName = UserDefaults.standard.string(forKey: Self.playerNameKey) ?? ""
        layout = UserDefaults.standard.data(forKey: Self.layoutKey)
            .flatMap { try? JSONDecoder().decode(ControllerLayout.self, from: $0) } ?? .standard
    }

    var statusText: String {
        let macName = connectedMac?.name ?? "the Mac"
        return switch status {
        case .connecting: "Connecting to \(macName)…"
        case .waitingForApproval: "Click Allow on \(macName)"
        case .connected(let slot): "\(effectiveName) · Player \(slot + 1)"
        case .full: "\(macName) already has 4 players"
        case .denied: "\(macName) didn’t allow this iPhone"
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
        let link = ControllerLink(to: mac.endpoint, identity: Self.identity, name: effectiveName) { [weak self] status in
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

    private var effectiveName: String {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "iPhone" : trimmed
    }

    /// This phone's long-term key. The Mac remembers it once the user allows the phone, so it has to
    /// survive app launches. Deleting the app creates a new identity that has to be allowed again.
    private static let identity: SecureChannel.PrivateKey = {
        if let stored = UserDefaults.standard.data(forKey: identityKey),
           let key = try? SecureChannel.PrivateKey(rawRepresentation: stored) {
            return key
        }
        let key = SecureChannel.PrivateKey()
        UserDefaults.standard.set(key.rawRepresentation, forKey: identityKey)
        return key
    }()
}
