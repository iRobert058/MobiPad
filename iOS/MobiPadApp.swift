import SwiftUI

@main
struct MobiPadApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            if model.connectedMac == nil {
                MacPickerView(model: model)
            } else {
                ControllerView(model: model)
            }
        }
    }
}
