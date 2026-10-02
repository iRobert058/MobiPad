import MobiPadProtocol
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The landscape controller (FR-03, UX-02). Each control is its own view with its own gesture, so
/// SwiftUI tracks their touches independently and they can be used at the same time (FR-04).
///
/// The controls go where the player's layout puts them. In edit mode they can be moved, resized and
/// hidden (UX-03).
struct ControllerView: View {
    typealias Control = ControllerLayout.Control

    let model: AppModel
    @State private var state = ControllerState()
    /// The layout being edited. Nil while playing.
    @State private var draft: ControllerLayout?
    @State private var selected: Control?
    /// Where the latest drag on each control started, and where the control was then.
    @State private var dragStarts: [Control: (touch: CGPoint, center: CGPoint)] = [:]
    /// Where the latest pinch started, and the control's scale then.
    @State private var pinchStart: (touch: CGPoint, scale: CGFloat)?

    /// Dragged controls snap to steps of this fraction of the screen, so they line up.
    private static let gridStep: CGFloat = 0.02

    private var layout: ControllerLayout { draft ?? model.layout }

    /// The controls of the controller the phone acts as.
    private var controls: [Control] {
        Control.allCases.filter { $0.kind == model.controllerKind }
    }

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.size
            ZStack {
                if draft != nil {
                    // Pinching empty space resizes the selected control, which small buttons need.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selected = nil }
                        .gesture(pinchGesture(selected))
                }
                ForEach(controls.filter { layout[$0].isShown }) { control in
                    placed(control, in: area)
                }
            }
        }
        .overlay(alignment: .top) {
            if draft == nil { statusPanel } else { editPanel }
        }
        .padding(16)
        .onChange(of: state) { _, newState in
            if draft == nil { model.send(newState) }
        }
        .onChange(of: model.controllerKind) {
            // The other controller has other buttons, so release everything.
            selected = nil
            state = ControllerState()
        }
        // FR-05: a light tap whenever a button goes down.
        .sensoryFeedback(.impact(weight: .light), trigger: state.buttons) { old, new in
            !new.subtracting(old).isEmpty
        }
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // System swipes (Control Center, Home) need a second swipe, so a thumb sliding off a control
        // doesn't open them mid-game.
        .defersSystemGestures(on: .all)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    // MARK: - Panels

    private var statusPanel: some View {
        VStack(spacing: 8) {
            Text(model.statusText)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                Menu(model.controllerKind.name) {
                    Picker("Controller", selection: Binding(
                        get: { model.controllerKind },
                        set: { model.controllerKind = $0 }
                    )) {
                        ForEach(ControllerKind.allCases) { kind in
                            Text(kind.name)
                        }
                    }
                }
                Button("Edit Layout") { startEditing() }
                Button("Disconnect", role: .destructive) { model.disconnect() }
            }
        }
        .font(.caption)
    }

    private var editPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Menu("Show/Hide") {
                    ForEach(controls) { control in
                        Toggle(control.name, isOn: isShown(control))
                    }
                }
                Button("Reset") {
                    withAnimation { draft?.reset(model.controllerKind) }
                    selected = nil
                }
                Button("Cancel") { stopEditing(saving: false) }
                Button("Done") { stopEditing(saving: true) }
                    .bold()
            }
            if let selected {
                HStack {
                    Text(selected.name)
                    Slider(value: scale(of: selected), in: ControllerLayout.scales)
                        .frame(width: 160)
                }
                .font(.caption)
            } else {
                Text("Drag a control to move it. Pinch or tap it to resize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Editing

    private func startEditing() {
        draft = model.layout
        // Release everything, so nothing stays pressed on the Mac while controls are being moved.
        state = ControllerState()
        model.send(state)
    }

    private func stopEditing(saving: Bool) {
        if saving, let draft { model.layout = draft }
        draft = nil
        selected = nil
    }

    private func moveGesture(_ control: Control, in area: CGSize) -> some Gesture {
        // Global, because the control moves along with the finger.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                selected = control
                // Keyed by where the touch started, so a drag the system cancelled (which never
                // calls onEnded) can't leave a stale start behind.
                let start: CGPoint
                if let previous = dragStarts[control], previous.touch == drag.startLocation {
                    start = previous.center
                } else {
                    start = center(of: control, in: area)
                    dragStarts[control] = (drag.startLocation, start)
                }
                let point = clamped(
                    CGPoint(x: start.x + drag.translation.width, y: start.y + drag.translation.height),
                    size: control.size(scale: layout[control].scale),
                    in: area
                )
                draft?[control].center = CGPoint(x: snapped(point.x / area.width), y: snapped(point.y / area.height))
            }
    }

    private func pinchGesture(_ control: Control?) -> some Gesture {
        MagnifyGesture()
            .onChanged { pinch in
                guard let control else { return }
                selected = control
                // Keyed by where the pinch started, like the drag starts.
                let start: CGFloat
                if let pinchStart, pinchStart.touch == pinch.startLocation {
                    start = pinchStart.scale
                } else {
                    start = layout[control].scale
                    pinchStart = (pinch.startLocation, start)
                }
                draft?[control].scale = Self.limited(start * pinch.magnification)
            }
    }

    private func isShown(_ control: Control) -> Binding<Bool> {
        Binding(
            get: { layout[control].isShown },
            set: { shown in
                draft?[control].isShown = shown
                if !shown, selected == control { selected = nil }
            }
        )
    }

    private func scale(of control: Control) -> Binding<CGFloat> {
        Binding(
            get: { layout[control].scale },
            set: { draft?[control].scale = Self.limited($0) }
        )
    }

    private static func limited(_ scale: CGFloat) -> CGFloat {
        min(max(scale, ControllerLayout.scales.lowerBound), ControllerLayout.scales.upperBound)
    }

    private func snapped(_ fraction: CGFloat) -> CGFloat {
        (fraction / Self.gridStep).rounded() * Self.gridStep
    }

    // MARK: - Placing controls

    private func placed(_ control: Control, in area: CGSize) -> some View {
        let scale = layout[control].scale
        let size = control.size(scale: scale)
        let isSelected = selected == control
        return view(for: control, scale: scale)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(draft == nil)
            .overlay {
                if draft != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary,
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [5, 4])
                        )
                        .contentShape(Rectangle())
                        .gesture(moveGesture(control, in: area))
                        .simultaneousGesture(pinchGesture(control))
                }
            }
            .position(center(of: control, in: area))
            .zIndex(isSelected ? 1 : 0)
    }

    /// Where the control goes on screen. A control near an edge is kept fully on screen, also on a
    /// smaller iPhone than the one the layout was made on.
    private func center(of control: Control, in area: CGSize) -> CGPoint {
        let placement = layout[control]
        return clamped(
            CGPoint(x: placement.center.x * area.width, y: placement.center.y * area.height),
            size: control.size(scale: placement.scale),
            in: area
        )
    }

    private func clamped(_ center: CGPoint, size: CGSize, in area: CGSize) -> CGPoint {
        func clamp(_ value: CGFloat, half: CGFloat, length: CGFloat) -> CGFloat {
            min(max(value, half), max(half, length - half))
        }
        return CGPoint(
            x: clamp(center.x, half: size.width / 2, length: area.width),
            y: clamp(center.y, half: size.height / 2, length: area.height)
        )
    }

    @ViewBuilder
    private func view(for control: Control, scale: CGFloat) -> some View {
        let size = Metrics.button * scale
        switch control {
        case .leftStick: ThumbStick(position: $state.leftStick, radius: Metrics.stickRadius * scale)
        case .rightStick: ThumbStick(position: $state.rightStick, radius: Metrics.stickRadius * scale)
        case .dpad:
            cross(
                scale: scale,
                top: button("▲", .dpadUp, size: size),
                left: button("◀", .dpadLeft, size: size),
                right: button("▶", .dpadRight, size: size),
                bottom: button("▼", .dpadDown, size: size)
            )
        case .faceButtons:
            cross(
                scale: scale,
                top: button("Y", .y, size: size),
                left: button("X", .x, size: size),
                right: button("B", .b, size: size),
                bottom: button("A", .a, size: size)
            )
        case .leftTrigger: trigger("LT", \.leftTrigger, size: size)
        case .leftShoulder: button("LB", .leftShoulder, size: size)
        case .rightShoulder: button("RB", .rightShoulder, size: size)
        case .rightTrigger: trigger("RT", \.rightTrigger, size: size)
        case .view: button("View", .view, size: size)
        case .menu: button("Menu", .menu, size: size)
        case .home: button("Home", .home, size: size)
        case .leftStickPress: button("L3", .leftStickPress, size: size)
        case .rightStickPress: button("R3", .rightStickPress, size: size)
        // The Wii Remote's buttons go out as the state buttons the Wii Remote profile in Dolphin expects.
        case .wiiDpad:
            cross(
                scale: scale,
                top: button("▲", .dpadUp, size: size),
                left: button("◀", .dpadLeft, size: size),
                right: button("▶", .dpadRight, size: size),
                bottom: button("▼", .dpadDown, size: size)
            )
        case .wiiA: button("A", .a, size: size)
        case .wiiB: button("B", .b, size: size)
        case .wiiOne: button("1", .x, size: size)
        case .wiiTwo: button("2", .y, size: size)
        case .wiiMinus: button("−", .view, size: size)
        case .wiiHome: button("Home", .home, size: size)
        case .wiiPlus: button("+", .menu, size: size)
        }
    }

    /// Four buttons in a plus shape: the D-pad and A/B/X/Y.
    private func cross(
        scale: CGFloat, top: PressableButton, left: PressableButton, right: PressableButton, bottom: PressableButton
    ) -> some View {
        VStack(spacing: Metrics.crossSpacing * scale) {
            top
            HStack(spacing: Metrics.button * scale) {
                left
                right
            }
            bottom
        }
    }

    private func button(_ label: String, _ button: ControllerState.Buttons, size: CGFloat) -> PressableButton {
        PressableButton(label: label, size: size, isPressed: Binding(
            get: { state.buttons.contains(button) },
            set: { pressed in
                if pressed { state.buttons.insert(button) } else { state.buttons.remove(button) }
            }
        ))
    }

    /// Triggers are all-or-nothing on a touchscreen.
    private func trigger(
        _ label: String, _ trigger: WritableKeyPath<ControllerState, UInt8>, size: CGFloat
    ) -> PressableButton {
        PressableButton(label: label, size: size, isPressed: Binding(
            get: { state[keyPath: trigger] > 0 },
            set: { pressed in state[keyPath: trigger] = pressed ? .max : 0 }
        ))
    }
}

/// Control sizes at scale 1.
private enum Metrics {
    static let button: CGFloat = 44
    static let stickRadius: CGFloat = 50
    /// Between the rows of the D-pad and A/B/X/Y.
    static let crossSpacing: CGFloat = 4
}

private extension ControllerLayout.Control {
    func size(scale: CGFloat) -> CGSize {
        let size: CGSize = switch self {
        case .leftStick, .rightStick:
            CGSize(width: Metrics.stickRadius * 2, height: Metrics.stickRadius * 2)
        case .dpad, .faceButtons, .wiiDpad:
            CGSize(width: Metrics.button * 3, height: Metrics.button * 3 + Metrics.crossSpacing * 2)
        case .leftTrigger, .leftShoulder, .rightShoulder, .rightTrigger,
             .view, .menu, .home, .leftStickPress, .rightStickPress,
             .wiiA, .wiiB, .wiiOne, .wiiTwo, .wiiMinus, .wiiHome, .wiiPlus:
            CGSize(width: Metrics.button, height: Metrics.button)
        }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// A button that stays pressed for as long as a finger is on it, and at least `minimumPress`.
///
/// iOS can hold back a lone touch and then deliver its start and end at the same moment (seen on the
/// right half of an iPhone 16 Pro in landscape), so a quick tap would otherwise never show up as pressed. `@GestureState` resets on its own when the system
/// cancels the touch (for example, when a notification comes in), so no button gets stuck.
private struct PressableButton: View {
    let label: String
    let size: CGFloat
    @Binding var isPressed: Bool
    @GestureState private var isTouched = false
    @State private var pressedAt: ContinuousClock.Instant?
    @State private var pendingRelease: Task<Void, Never>?

    /// Long enough for an emulator polling at 60 Hz to see a tap.
    private static let minimumPress: Duration = .milliseconds(50)

    var body: some View {
        Text(label)
            // Headline size at the standard button size.
            .font(.system(size: size * 17 / 44, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(Circle().fill(isPressed ? Color.accentColor : Color.secondary.opacity(0.3)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouched) { _, touched, _ in touched = true }
                    .onChanged { _ in press() }
                    .onEnded { _ in release() }
            )
            // A cancelled touch doesn't call onEnded.
            .onChange(of: isTouched) { _, touched in
                if !touched { release() }
            }
    }

    private func press() {
        guard pressedAt == nil else { return }
        pendingRelease?.cancel()
        pressedAt = .now
        isPressed = true
    }

    private func release() {
        guard let pressedAt else { return }
        self.pressedAt = nil
        let remaining = Self.minimumPress - (.now - pressedAt)
        guard remaining > .zero else {
            isPressed = false
            return
        }
        pendingRelease = Task {
            try? await Task.sleep(for: remaining)
            if !Task.isCancelled { isPressed = false }
        }
    }
}

/// An analog stick: the knob follows the finger within the base and springs back on release.
private struct ThumbStick: View {
    @Binding var position: ControllerState.Stick
    let radius: CGFloat
    @GestureState private var touch: CGPoint?

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
