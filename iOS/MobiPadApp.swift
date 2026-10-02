import SwiftUI

@main
struct MobiPadApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.connectedMac == nil {
                    MacPickerView(model: model)
                } else {
                    ControllerView(model: model)
                }
            }
            .preferredColorScheme(model.appearance.colorScheme)
        }
    }
}

private extension Appearance {
    /// Nil follows the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
