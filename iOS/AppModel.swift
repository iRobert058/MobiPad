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

    /// Light or dark, or following the phone (UX-05).
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// Which controller the phone acts as: the Classic Controller layout, or a Wii Remote with tilt.
    var controllerKind: ControllerKind {
        didSet { UserDefaults.standard.set(controllerKind.rawValue, forKey: Self.controllerKindKey) }
    }

    /// Where the controls sit on the controller screen (UX-03).
    var layout: ControllerLayout {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(layout), forKey: Self.layoutKey) }
    }

    private var browser: MacBrowser?
    private var link: ControllerLink?
    /// The buttons and sticks last sent, so tilt can be sent along with them.
    @ObservationIgnored private var lastState = ControllerState()
    /// The phone's tilt in the Wii Remote layout. Nil otherwise.
    @ObservationIgnored private var motion: ControllerState.Motion?
    /// Where the pointing Wii Remote points, for Cemu, which takes the pointer as a position.
    @ObservationIgnored private var pointer = PointerTracker()
    @ObservationIgnored private var lastMotionAt: ContinuousClock.Instant?
    /// Ignores status updates from a link that has since been replaced.
    private var linkToken = UUID()

    private static let playerNameKey = "playerName"
    private static let layoutKey = "controllerLayout"
    private static let appearanceKey = "appearance"
    private static let controllerKindKey = "controllerKind"
    private static let uprightPointingKey = "pointingLayoutIsUpright"
    private static let identityKey = "identityKey"

    init() {
        playerName = UserDefaults.standard.string(forKey: Self.playerNameKey) ?? ""
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey).flatMap(Appearance.init) ?? .system
        controllerKind = UserDefaults.standard.string(forKey: Self.controllerKindKey).flatMap(ControllerKind.init) ?? .classic
        var layout = UserDefaults.standard.data(forKey: Self.layoutKey)
            .flatMap { try? JSONDecoder().decode(ControllerLayout.self, from: $0) } ?? .standard
        // The pointing Wii Remote used to be held in landscape. Its old placements don't fit upright.
        if !UserDefaults.standard.bool(forKey: Self.uprightPointingKey) {
            layout.reset(.wiiPointer)
            UserDefaults.standard.set(try? JSONEncoder().encode(layout), forKey: Self.layoutKey)
            UserDefaults.standard.set(true, forKey: Self.uprightPointingKey)
        }
        self.layout = layout
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
            MainActor.assumeIsolated {
                guard let self else { return }
                self.macs = macs
                #if DEBUG
                // Launched with -connectToFirstMac: connects without a tap, for testing in the Simulator.
                if ProcessInfo.processInfo.arguments.contains("-connectToFirstMac"), self.connectedMac == nil, let mac = macs.first {
                    self.connect(to: mac)
                }
                #endif
            }
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
        lastState = ControllerState()
        motion = nil
        link.connect()
    }

    func disconnect() {
        link?.disconnect()
        link = nil
        linkToken = UUID()
        connectedMac = nil
        status = .disconnected
        lastState = ControllerState()
        motion = nil
    }

    func send(_ state: ControllerState) {
        // The pointing Wii Remote's Center button (sent as R3, for Dolphin) also recenters the pointer
        // sent to Cemu.
        if controllerKind == .wiiPointer, state.buttons.contains(.rightStickPress), !lastState.buttons.contains(.rightStickPress) {
            pointer.recenter()
        }
        lastState = state
        sendCurrentState()
    }

    /// Sends the phone's tilt with the buttons last sent. Nil stops sending motion.
    func send(motion: ControllerState.Motion?) {
        let now = ContinuousClock.now
        if let motion, let lastMotionAt {
            let elapsed = now - lastMotionAt
            pointer.update(motion, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        } else {
            pointer.recenter()
        }
        lastMotionAt = motion == nil ? nil : now
        self.motion = motion
        sendCurrentState()
    }

    private func sendCurrentState() {
        var state = lastState
        // Held sideways, the phone's left end is the Wii Remote's IR end. The phone turns the motion
        // itself rather than Dolphin, so one Dolphin profile works for every way of holding it.
        // Pointing, the phone is upright like a real remote, and its top already is the IR end.
        // A Joy-Con reports motion in its own axes: held sideways, its top end is the phone's right end;
        // upright, it's the phone's top.
        state.motion = switch controllerKind {
        case .wiiRemote: motion?.turnedSideways
        case .joyConSideways: motion?.turnedLikeSidewaysJoyCon
        // The GamePad is held in landscape like the phone, so the screen's axes are the pad's.
        case .classic, .wiiPointer, .joyConUpright, .wiiUGamePad: motion
        }
        // Cemu takes the Wii Remote's pointer from the DSU touch point. Dolphin works it out from the
        // motion and ignores the touch point unless a profile maps it.
        if controllerKind == .wiiPointer, motion != nil {
            let position = pointer.position
            state.touch = .init(id: 1, normalizedX: position.x, normalizedY: position.y)
        }
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

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var name: String {
        switch self {
        case .system: "Same as iPhone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
