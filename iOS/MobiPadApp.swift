import SwiftUI
import UIKit

@main
struct MobiPadApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    /// The pointing Wii Remote is held upright, like a real one aimed at the TV.
    private var isUpright: Bool { model.connectedMac != nil && model.controllerKind.isUpright }

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
            .onChange(of: isUpright, initial: true) { _, isUpright in
                AppDelegate.turnScreen(to: isUpright ? .portrait : .landscape)
            }
        }
    }
}

/// Turns the screen upright for the pointing Wii Remote, whichever way the phone is held.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Landscape until the controller screen asks for upright.
    @MainActor private static var orientations: UIInterfaceOrientationMask = .landscape

    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientations
    }

    @MainActor static func turnScreen(to orientations: UIInterfaceOrientationMask) {
        guard orientations != self.orientations else { return }
        self.orientations = orientations
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
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
