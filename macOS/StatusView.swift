import MobiPadDSU
import MobiPadNetwork
import MobiPadProtocol
import SwiftUI

/// Connection status (DR-03) and live input per player (FR-08).
struct StatusView: View {
    let model: CompanionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MobiPad").font(.headline)

            // Polls the host while the menu is open, rather than pushing every input to the UI.
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                let players = model.host.players()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<ControllerHost.slotCount, id: \.self) { slot in
                        PlayerRow(slot: slot, player: players.first { $0.slot == slot })
                    }
                }
            }

            Divider()
            serviceStatus
            dolphinSettings
            edenSettings
            Divider()
            testPlayerSettings
            Divider()
            keyboardSettings
            Divider()
            HStack {
                Text(approvedPhonesText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Forget") { model.forgetApprovedPhones() }
                    .disabled(model.approvedPhones.isEmpty)
            }
            Button("Quit MobiPad") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 340)
    }

    private var approvedPhonesText: String {
        switch model.approvedPhones.count {
        case 0: "No approved phones"
        case 1: "1 approved phone"
        case let count: "\(count) approved phones"
        }
    }

    @ViewBuilder private var dolphinSettings: some View {
        Button("Set Up Dolphin") { model.setUpDolphin() }
        Group {
            switch model.dolphinSetup {
            case nil:
                Text("Adds MobiPad to Dolphin, with a controller profile for each player.")
                    .foregroundStyle(.secondary)
            case .success(.installed):
                Text("Done. In Dolphin, open Controllers, set Port 1 to Standard Controller, click Configure, and load the profile “MobiPad Player 1”. Port 2 gets “MobiPad Player 2”, and so on. For Wii games, set Wii Remote 1 to Emulated Wii Remote instead, and load “MobiPad Wii Remote Player 1” (with tilt) or “MobiPad Classic Player 1”.")
                    .foregroundStyle(.secondary)
            case .success(.dolphinIsRunning):
                Text("Quit Dolphin first, because it overwrites its settings when it quits. Then click Set Up Dolphin again.")
                    .foregroundStyle(.orange)
            case .success(.dolphinNotFound):
                Text("Dolphin’s settings weren’t found. Open Dolphin once, quit it, and try again.")
                    .foregroundStyle(.orange)
            case .failure(let error):
                Text("Couldn’t set up Dolphin: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    @ViewBuilder private var edenSettings: some View {
        Button("Set Up Eden") { model.setUpEden() }
        Group {
            switch model.edenSetup {
            case nil:
                Text("Turns on Eden’s DSU controller, with a controller profile for each player.")
                    .foregroundStyle(.secondary)
            case .success(.installed):
                Text("Done. In Eden’s settings, open Controls, choose the profile “MobiPad Player 1” for Player 1, and click Load. Player 2 gets “MobiPad Player 2”, and so on; connect those players too. For the phone’s Joy-Con layouts, load “MobiPad Joy-Con Player 1” instead.")
                    .foregroundStyle(.secondary)
            case .success(.edenIsRunning):
                Text("Quit Eden first, because it overwrites its settings when it quits. Then click Set Up Eden again.")
                    .foregroundStyle(.orange)
            case .success(.edenNotFound):
                Text("Eden’s settings weren’t found. Open Eden once, quit it, and try again.")
                    .foregroundStyle(.orange)
            case .failure(let error):
                Text("Couldn’t set up Eden: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    @ViewBuilder private var testPlayerSettings: some View {
        Toggle("Test controller", isOn: Binding(
            get: { model.testPlayerSlot != nil },
            set: { model.setTestPlayerRunning($0) }
        ))
        if let slot = model.testPlayerSlot {
            Text("Player \(slot + 1) circles its sticks and presses A, B, X and Y in turn, so you can check an emulator sees MobiPad without a phone. Turn it off before mapping buttons.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.testPlayerFailed {
            Text("All \(ControllerHost.slotCount) player slots are taken.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var keyboardSettings: some View {
        Toggle("Player 1 as keyboard (for Ryujinx)", isOn: Binding(
            get: { model.isKeyboardEnabled },
            set: { model.setKeyboardEnabled($0) }
        ))
        if model.keyboardNeedsPermission {
            Text("Allow MobiPad under System Settings → Privacy & Security → Accessibility, then turn this on again.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if model.isKeyboardEnabled {
            Text("Player 1's buttons now type keys in whichever app is in front.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var serviceStatus: some View {
        switch model.dsuStatus {
        case .starting:
            Label("Starting…", systemImage: "hourglass")
        case .running:
            Label("In Cemu, add a DSU server at 127.0.0.1, port \(String(DSU.defaultPort)).", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label("Emulators can't connect: \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
        if case .failed(let message) = model.hostStatus {
            Label("Phones can't connect: \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

private struct PlayerRow: View {
    let slot: Int
    let player: ControllerHost.Player?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: player == nil ? "circle" : "circle.fill")
                .foregroundStyle(player == nil ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Player \(slot + 1)").font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let player {
                // Wii Remote modes: a level bubble that moves as the player tilts their phone.
                if let motion = player.state.motion {
                    Image(systemName: "gyroscope")
                        .foregroundStyle(.secondary)
                        .help("Tilt")
                    StickDot(stick: .init(
                        normalizedX: Double(motion.acceleration.x),
                        normalizedY: Double(motion.acceleration.y)
                    ))
                }
                StickDot(stick: player.state.leftStick)
                Text(pressedButtons(player.state))
                    .font(.caption.monospaced())
                    .frame(width: 90)
                StickDot(stick: player.state.rightStick)
            }
        }
    }

    private var detail: String {
        guard let player else { return "Empty" }
        guard let latency = player.latency else { return player.name }
        return "\(player.name) · \(latency.formatted(.units(allowed: [.milliseconds], width: .narrow)))"
    }

    private func pressedButtons(_ state: ControllerState) -> String {
        var names = Self.buttonNames.filter { state.buttons.contains($0.0) }.map(\.1)
        if state.leftTrigger > 0 { names.append("LT") }
        if state.rightTrigger > 0 { names.append("RT") }
        return names.isEmpty ? "–" : names.joined(separator: " ")
    }

    private static let buttonNames: [(ControllerState.Buttons, String)] = [
        (.a, "A"), (.b, "B"), (.x, "X"), (.y, "Y"),
        (.leftShoulder, "LB"), (.rightShoulder, "RB"),
        (.leftStickPress, "L3"), (.rightStickPress, "R3"),
        (.menu, "Menu"), (.view, "View"), (.home, "Home"),
        (.dpadUp, "↑"), (.dpadDown, "↓"), (.dpadLeft, "←"), (.dpadRight, "→"),
    ]
}

/// A stick position as a dot inside a ring.
private struct StickDot: View {
    let stick: ControllerState.Stick
    private let size: CGFloat = 22

    var body: some View {
        let reach = size / 2 - 3
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.5))
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .offset(
                    x: CGFloat(stick.x) / CGFloat(Int16.max) * reach,
                    y: -CGFloat(stick.y) / CGFloat(Int16.max) * reach
                )
        }
        .frame(width: size, height: size)
    }
}
