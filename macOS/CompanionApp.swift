import AppKit
import MobiPadDSU
import MobiPadKeyboard
import MobiPadNetwork
import MobiPadVideo
import SwiftUI

/// Menu bar app, so it keeps running in the background while a game has focus (DR-02).
@main
struct CompanionApp: App {
    @State private var model = CompanionModel()

    var body: some Scene {
        MenuBarExtra("MobiPad", systemImage: "gamecontroller") {
            StatusView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Phones connect to `host`; every state it receives goes straight to the DSU server, where
/// emulators such as Dolphin, Cemu and Eden pick it up, and optionally to the keyboard (Player 1 only).
@MainActor @Observable
final class CompanionModel {
    enum ServiceStatus: Equatable {
        case starting
        case running
        case failed(String)
    }

    let host: ControllerHost
    private let dsuServer: DSUServer
    private let gamePadStreamer: GamePadStreamer
    private let keyboard: KeyboardOutput
    private(set) var hostStatus = ServiceStatus.starting
    private(set) var dsuStatus = ServiceStatus.starting
    private(set) var isKeyboardEnabled = false
    private(set) var keyboardNeedsPermission = false
    /// The slot of the pretend player, while it runs.
    private(set) var testPlayerSlot: Int?
    private(set) var testPlayerFailed = false
    /// The result of the last click on Set Up Dolphin.
    private(set) var dolphinSetup: Result<DolphinSetup.Outcome, any Error>?
    /// The result of the last click on Set Up Cemu.
    private(set) var cemuSetup: Result<CemuSetup.Outcome, any Error>?
    /// The result of the last click on Set Up Eden.
    private(set) var edenSetup: Result<EdenSetup.Outcome, any Error>?
    /// Whether phones in the Wii U GamePad layout get Cemu's GamePad window. Off until the player turns
    /// it on, so the Mac never starts recording the screen on its own.
    private(set) var isGamePadScreenEnabled: Bool
    /// Screen Recording isn't allowed yet (or wasn't when the switch was turned on).
    private(set) var gamePadScreenNeedsPermission = false
    /// Identity key (base64) → the name the phone had when it was approved.
    private(set) var approvedPhones: [String: String]
    private var approvalQueue: [ControllerHost.ApprovalRequest] = []
    private var isAskingForApproval = false

    private static let approvedPhonesKey = "approvedPhones"
    private static let gamePadScreenKey = "gamePadScreenEnabled"

    init() {
        let dsuServer = DSUServer()
        let keyboard = KeyboardOutput()
        let relay = ApprovalRelay()
        let approvedPhones = UserDefaults.standard.dictionary(forKey: Self.approvedPhonesKey) as? [String: String] ?? [:]
        self.dsuServer = dsuServer
        self.keyboard = keyboard
        self.approvedPhones = approvedPhones
        let host = ControllerHost(approvedPhones: Set(approvedPhones.keys.compactMap { Data(base64Encoded: $0) })) { request in
            Task { @MainActor in relay.model?.askForApproval(request) }
        } output: { slot, state in
            if let state {
                dsuServer.update(slot: slot, state: state)
            } else {
                dsuServer.disconnect(slot: slot)
            }
            if slot == 0 {
                keyboard.update(state)
            }
        }
        self.host = host

        // Cemu's GamePad window, for phones in the Wii U GamePad layout.
        let streamer = GamePadStreamer(source: CemuWindowSource()) { fragment, slots in
            host.sendVideo(fragment, to: slots)
        } sendStatus: { status, slot in
            host.sendVideoStatus(status, to: slot)
        }
        host.onVideoRequest { slot, keyframe in streamer.request(slot: slot, keyframe: keyframe) }
        gamePadStreamer = streamer
        isGamePadScreenEnabled = UserDefaults.standard.bool(forKey: Self.gamePadScreenKey)
        gamePadScreenNeedsPermission = isGamePadScreenEnabled && !CGPreflightScreenCaptureAccess()
        streamer.setEnabled(isGamePadScreenEnabled)

        relay.model = self
        Task { await start() }
    }

    func setKeyboardEnabled(_ enabled: Bool) {
        if enabled, !KeyboardOutput.hasPermission {
            KeyboardOutput.requestPermission()
            keyboardNeedsPermission = true
            return
        }
        keyboardNeedsPermission = false
        isKeyboardEnabled = enabled
        keyboard.setEnabled(enabled)
    }

    func setTestPlayerRunning(_ running: Bool) {
        if running {
            testPlayerSlot = host.startTestPlayer()
            testPlayerFailed = testPlayerSlot == nil
        } else {
            host.stopTestPlayer()
            testPlayerSlot = nil
            testPlayerFailed = false
        }
    }

    /// Turning it on asks macOS for Screen Recording the first time; macOS shows its own prompt.
    func setGamePadScreenEnabled(_ enabled: Bool) {
        isGamePadScreenEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.gamePadScreenKey)
        gamePadStreamer.setEnabled(enabled)
        gamePadScreenNeedsPermission = enabled && !CGPreflightScreenCaptureAccess()
        if gamePadScreenNeedsPermission {
            gamePadScreenNeedsPermission = !CGRequestScreenCaptureAccess()
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func setUpDolphin() {
        dolphinSetup = Result {
            try DolphinSetup.install {
                !NSRunningApplication.runningApplications(withBundleIdentifier: "org.dolphin-emu.dolphin").isEmpty
            }
        }
    }

    func setUpCemu() {
        cemuSetup = Result { try CemuSetup.install() }
    }

    func setUpEden() {
        edenSetup = Result {
            try EdenSetup.install {
                !NSRunningApplication.runningApplications(withBundleIdentifier: EdenSetup.bundleIdentifier).isEmpty
            }
        }
    }

    /// Every phone has to be allowed again; connected phones are disconnected.
    func forgetApprovedPhones() {
        host.revokeAllApprovals()
        approvedPhones = [:]
        UserDefaults.standard.removeObject(forKey: Self.approvedPhonesKey)
    }

    private func start() async {
        do {
            _ = try await dsuServer.start()
            dsuStatus = .running
        } catch {
            dsuStatus = .failed(error.localizedDescription)
        }
        do {
            _ = try await host.start()
            hostStatus = .running
        } catch {
            hostStatus = .failed(error.localizedDescription)
        }
    }

    /// Asks one phone at a time, even when several arrive together.
    fileprivate func askForApproval(_ request: ControllerHost.ApprovalRequest) {
        approvalQueue.append(request)
        guard !isAskingForApproval else { return }
        isAskingForApproval = true
        defer { isAskingForApproval = false }

        while !approvalQueue.isEmpty {
            let request = approvalQueue.removeFirst()
            let alert = NSAlert()
            alert.messageText = "Allow “\(request.name)” to connect?"
            alert.informativeText = "This iPhone wants to use MobiPad as a controller on this Mac. Only allow phones you recognize."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Don’t Allow")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                host.approve(request.identity)
                approvedPhones[request.identity.base64EncodedString()] = request.name
                UserDefaults.standard.set(approvedPhones, forKey: Self.approvedPhonesKey)
            } else {
                host.deny(request.identity)
            }
        }
    }
}

/// Lets the host's approval callback reach the model, which doesn't exist yet when the host is created.
@MainActor
private final class ApprovalRelay {
    weak var model: CompanionModel?
}
