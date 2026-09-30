#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation
import MobiPadProtocol

/// Turns controller states into key presses in whichever app has focus.
///
/// macOS only delivers these once the user allows MobiPad under Privacy & Security →
/// Accessibility. All state lives on `queue`, so the methods can be called from anywhere.
public final class KeyboardOutput: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MobiPad.KeyboardOutput")
    private let mapping: KeyboardMapping
    private let source = CGEventSource(stateID: .hidSystemState)
    private var isEnabled = false
    private var pressed: Set<CGKeyCode> = []

    public init(mapping: KeyboardMapping = .default) {
        self.mapping = mapping
    }

    public static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that leads the user to the Accessibility settings.
    public static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Turning it off releases every key it holds down.
    public func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            isEnabled = enabled
            if !enabled {
                press([])
            }
        }
    }

    /// Presses and releases keys to match the state. Nil (the controller left) releases everything,
    /// so no key stays stuck.
    public func update(_ state: ControllerState?) {
        queue.async { [self] in
            guard isEnabled else { return }
            press(state.map(mapping.keys(for:)) ?? [])
        }
    }

    private func press(_ keys: Set<CGKeyCode>) {
        for key in pressed.subtracting(keys) {
            post(key, down: false)
        }
        for key in keys.subtracting(pressed) {
            post(key, down: true)
        }
        pressed = keys
    }

    private func post(_ key: CGKeyCode, down: Bool) {
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)?.post(tap: .cghidEventTap)
    }
}
#endif
