import SwiftUI
import UIKit

@main
struct MobiPadApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    /// The start screen turns with the phone. The controller is landscape, except the pointing Wii
    /// Remote, which is held upright like a real one aimed at the TV.
    private var orientations: UIInterfaceOrientationMask {
        guard model.connectedMac != nil else { return .allButUpsideDown }
        return model.controllerKind.isUpright ? .portrait : .landscape
    }

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
            .onChange(of: orientations, initial: true) { _, orientations in
                AppDelegate.turnScreen(to: orientations)
            }
        }
    }
}

/// Turns the screen to the orientations each screen allows, whichever way the phone is held.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The app opens on the start screen, which turns with the phone.
    @MainActor private static var orientations: UIInterfaceOrientationMask = .allButUpsideDown

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
