import MobiPadNetwork
import MobiPadProtocol
import SwiftUI

/// Asks for the player's name and lists the Macs running MobiPad on this network (FR-01).
struct MacPickerView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Your name", text: $model.playerName)
                        .textContentType(.nickname)
                        .autocorrectionDisabled()
                        .onChange(of: model.playerName) { _, name in
                            if name.count > Message.maxNameLength {
                                model.playerName = String(name.prefix(Message.maxNameLength))
                            }
                        }
                } footer: {
                    Text("Shown on the Mac, so you can tell the players apart.")
                }

                Section {
                    Picker("Controller", selection: $model.controllerKind) {
                        ForEach(ControllerKind.allCases) { kind in
                            Text(kind.name)
                        }
                    }
                } footer: {
                    Text("The Wii Remotes use the phone’s motion, for Wii games in Dolphin: sideways for steering, pointing for games like Wii Party.")
                }

                Section("Macs on this network") {
                    if model.macs.isEmpty {
                        ContentUnavailableView(
                            "Looking for Macs",
                            systemImage: "desktopcomputer",
                            description: Text("Open MobiPad on your Mac, and make sure both are on the same Wi-Fi network.")
                        )
                    }
                    ForEach(model.macs) { mac in
                        Button {
                            model.connect(to: mac)
                        } label: {
                            Label(mac.name, systemImage: "desktopcomputer")
                        }
                    }
                }
            }
            .navigationTitle("MobiPad")
            .toolbar {
                Menu {
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.name)
                        }
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
            }
        }
        .onAppear { model.startBrowsing() }
    }
}
