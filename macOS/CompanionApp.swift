import MobiPadDSU
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

/// Phones connect to `host`; every state it receives goes straight to the DSU server,
/// where emulators such as Dolphin pick it up.
@MainActor @Observable
final class CompanionModel {
    enum ServiceStatus: Equatable {
        case starting
        case running
        case failed(String)
    }

    let host: ControllerHost
    private let dsuServer: DSUServer
    private(set) var hostStatus = ServiceStatus.starting
    private(set) var dsuStatus = ServiceStatus.starting

    init() {
        let dsuServer = DSUServer()
        self.dsuServer = dsuServer
        host = ControllerHost { slot, state in
            if let state {
                dsuServer.update(slot: slot, state: state)
            } else {
                dsuServer.disconnect(slot: slot)
            }
        }
        Task { await start() }
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
}
