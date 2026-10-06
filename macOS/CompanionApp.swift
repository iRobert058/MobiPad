import AppKit
import MobiPadDSU
import MobiPadKeyboard
import MobiPadNetwork
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
/// emulators such as Dolphin and Cemu pick it up, and optionally to the keyboard (Player 1 only).
/// Rumble goes the other way: from an emulator, through the DSU server and `host`, to the phone.
@MainActor @Observable
final class CompanionModel {
    enum ServiceStatus: Equatable {
        case starting
        case running
        case failed(String)
    }

    let host: ControllerHost
    private let dsuServer: DSUServer
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
    /// Identity key (base64) → the name the phone had when it was approved.
    private(set) var approvedPhones: [String: String]
    private var approvalQueue: [ControllerHost.ApprovalRequest] = []
    private var isAskingForApproval = false

    private static let approvedPhonesKey = "approvedPhones"

    init() {
        let rumbleRelay = RumbleRelay()
        let dsuServer = DSUServer { slot, intensity in
            rumbleRelay.host?.rumble(slot: slot, intensity: intensity)
        }
        let keyboard = KeyboardOutput()
        let relay = ApprovalRelay()
        let approvedPhones = UserDefaults.standard.dictionary(forKey: Self.approvedPhonesKey) as? [String: String] ?? [:]
        self.dsuServer = dsuServer
        self.keyboard = keyboard
        self.approvedPhones = approvedPhones
        host = ControllerHost(approvedPhones: Set(approvedPhones.keys.compactMap { Data(base64Encoded: $0) })) { request in
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
        relay.model = self
        rumbleRelay.host = host
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

    func setUpDolphin() {
        dolphinSetup = Result {
            try DolphinSetup.install {
                !NSRunningApplication.runningApplications(withBundleIdentifier: "org.dolphin-emu.dolphin").isEmpty
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

/// Lets the DSU server's rumble reach the host, which doesn't exist yet when the server is created.
/// Set once, before the server starts.
private final class RumbleRelay: @unchecked Sendable {
    weak var host: ControllerHost?
}
