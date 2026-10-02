# Tilt controls: notes

Branch: `tilt-controls` (made from `main` on 2026-10-03). Nothing is pushed or merged.

## Progress

- **Done:** research; plan; steps 1–5 (motion in the state, conversion, DSU output, Dolphin profiles, controller choice and Wii Remote layout); step 6 (`iOS/TiltSensor.swift`: Core Motion at 60 Hz in Wii Remote mode, sent with the buttons, steering indicator).
- **Working on:** step 7 (show each player's tilt in the Mac menu).
- **Next step:** in `macOS/StatusView.swift`, show a small steering indicator in a player's row when their state has motion.
- **Half-finished or broken:** nothing.

## How input gets to Dolphin today

1. `iOS/ControllerView.swift` keeps a `ControllerState` (buttons, two sticks, two triggers) and hands every change to `AppModel.send`.
2. `ControllerLink` (MobiPadNetwork) seals it as `SessionMessage.state` and sends it over UDP. It's resent every 50 ms.
3. On the Mac, `ControllerHost` opens it and calls its output with `(slot, state)`.
4. `CompanionModel` passes it to `DSUServer.update(slot:state:)` (and to the keyboard output for Player 1).
5. `DSU.padData` builds the 100-byte cemuhook packet. The six motion fields (accelerometer x/y/z in g, gyro pitch/yaw/roll in °/s) are always zero today.
6. Dolphin's DSU client (`DualShockUDPClient.cpp`) reads that packet as device `DSUClient/<slot>/MobiPad`.

## How Dolphin takes motion (checked in Dolphin's source, master, 2026-10-03)

- The DSU client exposes motion as inputs: `Accel Up/Down/Left/Right/Forward/Backward` and `Gyro Pitch Up/Down`, `Gyro Roll Left/Right`, `Gyro Yaw Left/Right`.
  - Accel Up = −accel_y, Left = +accel_x, Forward = +accel_z (g, turned into m/s²).
  - Gyro Pitch Up = +pitch, Roll Right = +roll, Yaw Right = +yaw (°/s, turned into rad/s).
- The emulated Wii Remote has an **Accelerometer** (`IMUAccelerometer`) and **Gyroscope** (`IMUGyroscope`) group under Motion Input. Dolphin's own default mapping binds them one to one (`IMUAccelerometer/Up = Accel Up`, and so on). When they're bound, Dolphin uses this real motion instead of its simulated tilt.
  - Dolphin's frame for this data is x = left, y = backward, z = up. At rest, face up, the accelerometer reads +1 g up.
- **"Sideways Wii Remote"** (`Options/Sideways Wiimote` in the profile) rotates the D-pad *and* the motion data by 90°. So a controller held like a normal landscape gamepad becomes a Wii Remote held sideways, with its IR end to the left. That's how Dolphin expects any motion controller (a DS4, a Switch Pro Controller, a phone) to act as a sideways remote.
- Wii Remote profiles live in `Config/Profiles/Wiimote/`. Keys: `Buttons/A`, `Buttons/B`, `Buttons/1`, `Buttons/2`, `Buttons/-`, `Buttons/+`, `Buttons/Home`, `D-Pad/Up`…, `IMUAccelerometer/Up`…, `IMUGyroscope/Pitch Up`…, `Options/Sideways Wiimote`, `Extension` (`None` or `Classic`), and `Classic/Buttons/A`, `Classic/Left Stick/Up`, `Classic/Triggers/L-Analog` and so on for the Classic Controller.

## Plan

The phone reports its motion like a normal landscape controller. The Wii Remote profile in Dolphin turns on Sideways, so Dolphin does the rotation. In order, with a commit after each:

1. **Wire format.** Add `ControllerState.Motion` (acceleration in g, rotation rate in °/s, in the landscape controller's frame). Send it as an optional 24-byte block after the existing 16-byte state. A state without the block decodes as before, so a phone without motion is unaffected.
2. **Sensor conversion.** A pure function (in MobiPadProtocol, so it's tested on the Mac) that turns Core Motion's portrait-axis readings into that landscape frame, for both landscape directions.
3. **DSU output.** Fill the six motion fields from the state, in Dolphin's conventions. Zero when the state has no motion, as now. Tests decode the packet the way Dolphin does.
4. **Dolphin profiles.** Set Up Dolphin also writes Wii Remote profiles (buttons, D-pad, accelerometer, gyroscope, Sideways on) and Classic Controller profiles (a Wii Remote with the Classic Controller extension) for each player. The GameCube profiles stay as they are.
5. **Controller choice on the phone.** "Classic Controller" (today's layout) or "Wii Remote" (sideways layout: D-pad, A, B, 1, 2, −, Home, +). The layout editor keeps working for both.
6. **Tilt.** In Wii Remote mode the phone reads its motion sensors at 60 Hz and sends them with the buttons. A small steering-wheel indicator shows the tilt.
7. **Mac menu.** Show each player's tilt next to their buttons.
8. **Docs.** README and the final notes.

## Decisions

- **The phone acts as a landscape controller; Dolphin's Sideways option does the rotation.** That matches Dolphin's own design, keeps the D-pad and motion consistent, and means the data would also make sense to other DSU clients.
- **Motion travels inside the state snapshot, not as a separate message.** The "full snapshot" design stays intact (one packet carries everything), and the DSU packet already has fields for it.
- **The protocol version stays at 3.** The motion block is optional. A phone built before this change (classic layout only) still works with the new Mac app. A new phone in Wii Remote mode needs the new Mac app: an older Mac app drops states with motion.
- **Frame of `Motion`:** x points to the right edge of the screen as the player holds it, y to the top edge, z out of the screen. Acceleration is what an accelerometer measures: +1 g on z when the phone lies face up. Rotation follows the right-hand rule.
- **Wii Remote buttons map onto existing state buttons:** A → A, B → B, 1 → X, 2 → Y, − → View, + → Menu, Home → Home. Over DSU these are Cross, Circle, Square, Triangle, Share, Options and PS, and the Wii Remote profile maps them back.
- **Set Up Dolphin writes all three profile kinds at once** (GameCube, Wii Remote, Classic Controller, four players each), so there's still one button. The GameCube profiles are unchanged. Two existing tests listed exactly the four GameCube profile names in the outcome; I updated those expectations to the full list of twelve and kept their checks of the GameCube files. No test was removed or skipped.
- **Classic Controller profiles match buttons by name**, like the GameCube profiles: A → A, B → B, X → X, Y → Y, LB/RB → L/R, LT/RT → ZL/ZR, View → −, Menu → +.

- **Wii Remote layout:** D-pad and A on the left, 1 and 2 (larger) on the right, B top left (where the trigger is when held sideways), and −, Home, + in the middle. The Wii Remote controls are separate controls in the same saved layout, so each controller keeps its own positions, and the editor's Show/Hide and Reset only touch the current controller. Switching controllers releases every button.
- **The controller can be chosen on the start screen and switched on the controller screen** (a menu next to Edit Layout), so there's no need to disconnect to switch.
- **I didn't look at the new layout in the Simulator,** because the Simulator keeps its data outside the project folder. I checked the geometry by calculation instead: no controls overlap on the smallest or a large iPhone.

- **Tilt only runs in Wii Remote mode on the controller screen,** and pauses in the layout editor. When it stops, the phone sends one state without motion, so Dolphin sees the motion return to zero rather than freeze at the last reading.
- **Motion is kept out of the controller screen's own state.** `AppModel` combines the last buttons with the latest tilt, so 60 readings a second don't redraw the whole screen; only the small steering indicator redraws.
- **No permission prompt is needed:** reading the accelerometer and gyroscope with `CMMotionManager` doesn't require one (only activity and step counting do), so `Info.plist` is unchanged.
- **Which way round the phone is held** comes from the window scene's interface orientation, read with every sample. Both landscape directions are supported, as before.

## For you to decide

Nothing yet.
