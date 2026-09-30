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
            Divider()
            Button("Quit MobiPad") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 340)
    }

    @ViewBuilder private var serviceStatus: some View {
        switch model.dsuStatus {
        case .starting:
            Label("Starting…", systemImage: "hourglass")
        case .running:
            Label("In Dolphin, add a DSU server at 127.0.0.1, port \(String(DSU.defaultPort)) (Controllers → Alternate Input Sources).", systemImage: "info.circle")
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
