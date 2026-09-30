import MobiPadProtocol
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The landscape controller layout (FR-03, UX-02). Each control is its own view with its own
/// gesture, so SwiftUI tracks their touches independently and they can be used at the same time (FR-04).
struct ControllerView: View {
    let model: AppModel
    @State private var state = ControllerState()

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                trigger("LT", \.leftTrigger)
                button("LB", .leftShoulder)
                Spacer()
                button("RB", .rightShoulder)
                trigger("RT", \.rightTrigger)
            }
            HStack {
                VStack(spacing: 16) {
                    ThumbStick(position: $state.leftStick)
                    dpad
                }
                Spacer()
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        button("View", .view)
                        button("Menu", .menu)
                    }
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Disconnect", role: .destructive) { model.disconnect() }
                        .font(.caption)
                }
                Spacer()
                VStack(spacing: 16) {
                    faceButtons
                    ThumbStick(position: $state.rightStick)
                }
            }
        }
        .padding(16)
        .onChange(of: state) { _, newState in model.send(newState) }
        // FR-05: a light tap whenever a button goes down.
        .sensoryFeedback(.impact(weight: .light), trigger: state.buttons) { old, new in
            !new.subtracting(old).isEmpty
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    private var faceButtons: some View {
        VStack(spacing: 4) {
            button("Y", .y)
            HStack(spacing: 44) {
                button("X", .x)
                button("B", .b)
            }
            button("A", .a)
        }
    }

    private var dpad: some View {
        VStack(spacing: 4) {
            button("▲", .dpadUp)
            HStack(spacing: 44) {
                button("◀", .dpadLeft)
                button("▶", .dpadRight)
            }
            button("▼", .dpadDown)
        }
    }

    private func button(_ label: String, _ button: ControllerState.Buttons) -> PressableButton {
        PressableButton(label: label, isPressed: Binding(
            get: { state.buttons.contains(button) },
            set: { pressed in
                if pressed { state.buttons.insert(button) } else { state.buttons.remove(button) }
            }
        ))
    }

    /// Triggers are all-or-nothing on a touchscreen.
    private func trigger(_ label: String, _ trigger: WritableKeyPath<ControllerState, UInt8>) -> PressableButton {
        PressableButton(label: label, isPressed: Binding(
            get: { state[keyPath: trigger] > 0 },
            set: { pressed in state[keyPath: trigger] = pressed ? .max : 0 }
        ))
    }
}

/// A button that stays pressed for as long as a finger is on it. `@GestureState` resets on its own
/// when the system cancels the touch (for example, when a notification comes in), so no button gets stuck.
private struct PressableButton: View {
    let label: String
    @Binding var isPressed: Bool
    @GestureState private var isTouched = false

    var body: some View {
        Text(label)
            .font(.headline)
            .minimumScaleFactor(0.5)
            .frame(width: 44, height: 44)
            .background(Circle().fill(isPressed ? Color.accentColor : Color.secondary.opacity(0.3)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouched) { _, touched, _ in touched = true }
            )
            .onChange(of: isTouched) { _, touched in isPressed = touched }
    }
}

/// An analog stick: the knob follows the finger within the base and springs back on release.
private struct ThumbStick: View {
    @Binding var position: ControllerState.Stick
    @GestureState private var touch: CGPoint?

    private let radius: CGFloat = 50

    var body: some View {
        let offset = knobOffset
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.secondary.opacity(0.6))
                .frame(width: radius, height: radius)
                .offset(offset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touch) { drag, touch, _ in touch = drag.location }
        )
        .onChange(of: touch) {
            let offset = knobOffset
            // Screen y points down; stick y points up.
            position = .init(normalizedX: offset.width / radius, normalizedY: -offset.height / radius)
        }
    }

    private var knobOffset: CGSize {
        guard let touch else { return .zero }
        let x = touch.x - radius
        let y = touch.y - radius
        let scale = min(1, radius / max(hypot(x, y), 1))
        return CGSize(width: x * scale, height: y * scale)
    }
}
