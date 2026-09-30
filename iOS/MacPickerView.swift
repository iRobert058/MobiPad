import MobiPadNetwork
import SwiftUI

/// Lists the Macs running MobiPad on this network (FR-01).
struct MacPickerView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.macs.isEmpty {
                    ContentUnavailableView(
                        "Looking for Macs",
                        systemImage: "desktopcomputer",
                        description: Text("Open MobiPad on your Mac, and make sure both are on the same Wi-Fi network.")
                    )
                } else {
                    List(model.macs) { mac in
                        Button {
                            model.connect(to: mac)
                        } label: {
                            Label(mac.name, systemImage: "desktopcomputer")
                        }
                    }
                }
            }
            .navigationTitle("Connect to a Mac")
        }
        .onAppear { model.startBrowsing() }
    }
}
