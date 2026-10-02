# Tilt controls: notes

Branch: `tilt-controls`, made from `main` on 2026-10-03. Nothing is pushed or merged, and `main` is untouched.

## Progress

- **Done:** all eight steps of the plan. The package tests pass (69 tests), and both apps build, including the iPhone app for a real device.
- **Working on:** nothing.
- **Next step:** your manual test on a real iPhone with Dolphin (checklist below).
- **Half-finished or broken:** nothing known. Tilt has not run on a real device or in Dolphin yet.

## What you get

- On the phone, choose **Classic Controller** (today's layout, no tilt) or **Wii Remote** (a sideways Wii Remote: D-pad, A, B, 1, 2, −, Home, +). Choose on the start screen, or with the new menu next to Edit Layout on the controller screen.
- In Wii Remote mode the phone reads its accelerometer and gyroscope 60 times a second and sends them with the buttons. A steering wheel next to the player name turns as you tilt; the Mac menu shows the same wheel per player.
- **Set Up Dolphin** in the Mac menu now also writes, per player, **MobiPad Wii Remote Player N** (buttons, D-pad, accelerometer, gyroscope, Sideways Wii Remote on) and **MobiPad Classic Player N** (a Wii Remote with the Classic Controller extension). The GameCube profiles are unchanged.
- Everything else works as before. In Classic Controller mode the phone sends exactly what it sent before, and the DSU motion fields stay zero, so Cemu, Ryujinx (keyboard) and the GameCube profiles are unaffected.

## Commits

1. `54cd51a`: your earlier uncommitted work, committed as the base (Set Up Dolphin, appearance setting, per-direction session keys, app icon, shared schemes). It was uncommitted on `main`, and committing it separately keeps the tilt commits reviewable.
2. `f7e6936`: these notes, with the research and plan.
3. `cd25db8`: motion in the controller state and the wire format.
4. `38a65a9`: converting Core Motion readings into the controller's frame.
5. `0e0c165`: sending the motion to Dolphin over DSU.
6. `d2c92a2`: Wii Remote and Classic Controller profiles from Set Up Dolphin.
7. `3057ce3`: the controller choice and the Wii Remote layout on the phone.
8. `9910107`: reading tilt in Wii Remote mode.
9. `32aa156`: tilt in the Mac menu.
10. The last commit: README, these final notes, and two small fixes in the iPhone code: one shared motion manager, and the last sent buttons cleared on connect and disconnect.

## Files changed

Shared package (MobiPadKit):
- `MobiPadProtocol/ControllerState.swift`: `ControllerState.motion` and the `Motion` type, with `steeringAngle`.
- `MobiPadProtocol/Message.swift`: the optional 24-byte motion block after the 16-byte state.
- `MobiPadProtocol/MotionConversion.swift` (new): Core Motion readings → the controller's frame, for both landscape directions.
- `MobiPadDSU/DSUMessages.swift`: the six DSU motion fields, in Dolphin's directions.
- `MobiPadDSU/DolphinSetup.swift`: the Wii Remote and Classic Controller profiles.
- Tests: `MessageTests`, `MotionConversionTests` (new), `DSUMotionTests` (new), `DolphinSetupTests`, `EndToEndTests`.

iPhone app:
- `iOS/TiltSensor.swift` (new): Core Motion at 60 Hz.
- `iOS/ControllerLayout.swift`: `ControllerKind` and the Wii Remote controls with their standard positions.
- `iOS/ControllerView.swift`: the layout per controller, the controller menu, tilt start and stop, the steering indicator.
- `iOS/AppModel.swift`: the saved controller choice, and sending tilt with the last buttons.
- `iOS/MacPickerView.swift`: the controller picker on the start screen.

Mac app: `macOS/StatusView.swift` (the "Done" text after Set Up Dolphin, and the tilt wheel per player).

Docs: `README.md` and this file.

## Test by hand on a real iPhone with Dolphin

1. Run both apps from Xcode (MobiPadCompanion, then MobiPad on the phone). Both need this version: an older Mac app ignores a phone while it tilts.
2. Click **Set Up Dolphin**. In Dolphin's profiles folder there should now be four Wii Remote and four Classic profiles next to the GameCube ones.
3. In Dolphin: Controllers → **Wii Remote 1: Emulated Wii Remote** → Configure → load **MobiPad Wii Remote Player 1**. Check that:
   - Options shows **Sideways Wii Remote** ticked.
   - The **Motion Input** tab shows Accelerometer and Gyroscope mapped to `Accel …` and `Gyro …`, and its preview moves when you tilt the phone.
4. On the phone choose **Wii Remote**. The steering wheel by your name should turn as you tilt, and the Mac menu's wheel for your player too.
5. In Mario Kart Wii, play with the **Wii Wheel / sideways Wii Remote** controls, holding the phone like a steering wheel with the screen toward you:
   - Turning the phone clockwise should steer **right**. If it steers left, tell me: that would mean a sign is flipped, which is a one-line fix in `DSU.motionFields`.
   - Do the same with the phone turned the other way round (camera on the other side). Steering should still be correct.
   - Buttons: 2 accelerates, 1 brakes, B drifts, the D-pad uses items, + pauses.
   - Shake the phone for tricks and wheelies.
   - Menus: try navigating with the D-pad. Dolphin may also move the pointer with the phone's motion ("Point" under Motion Input); note whether that gets in the way.
6. With the phone on **Classic Controller**, load **MobiPad Classic Player 1** in Dolphin and try a Wii game that supports the Classic Controller (Mario Kart Wii does).
7. Check that nothing else changed: the GameCube profile in Dolphin, Cemu, and Ryujinx with "Player 1 as keyboard", all with the phone on Classic Controller.
8. On the phone: Edit Layout in Wii Remote mode (tilt should pause while editing), switching controllers while connected, and battery and heat after a long session with tilt.
9. With your friend: a phone with yesterday's build should still work with the new Mac app on the Classic Controller layout.

## Decisions

- **The phone reports its motion as a normal landscape controller, and Dolphin's "Sideways Wii Remote" option turns it into a sideways remote.** Dolphin's Sideways option rotates both the D-pad and the motion data by a quarter turn (`GetOrientation()` in WiimoteEmu.cpp), and that's how it treats every motion controller. The profile turns the option on, so the phone's left end becomes the remote's IR end, and the on-screen D-pad works in screen directions.
- **Frame of `Motion`:** x points to the right edge of the screen as the player holds it, y to the top edge, z out of the screen. Acceleration is what an accelerometer measures (+1 g on z when lying face up); rotation follows the right-hand rule, in °/s.
- **Mapping to Dolphin** (from `DualShockUDPClient.cpp`): accelerometer x = left (−x), y = −up (−z), z = forward (+y); gyro pitch = +x, yaw = −z, roll = +y. The Wii Remote profile maps each `IMUAccelerometer`/`IMUGyroscope` direction to the DSU input of the same name, as Dolphin's own defaults do. `DSUMotionTests` read the packet the way Dolphin does, including its Sideways rotation.
- **Motion travels inside the state snapshot** as an optional block, not as a separate message. One packet keeps carrying everything, and the DSU packet already had the fields.
- **The protocol version stays at 3.** Phones without tilt send the same 16 bytes as before, so a phone with an older build keeps working with the new Mac app. Only a tilting phone needs the new Mac app. The alternative, bumping the version, would have locked older phones out entirely.
- **Wii Remote buttons reuse the existing state buttons:** A → A, B → B, 1 → X, 2 → Y, − → View, + → Menu, Home → Home (over DSU: Cross, Circle, Square, Triangle, Share, Options, PS). The Wii Remote profile maps them back, so the wire format and the Mac side needed no new buttons.
- **Set Up Dolphin writes all three profile kinds at once**, so there's still one button. Two existing tests listed exactly the four GameCube profile names in the outcome. I updated those two expectations to the full list of twelve and kept their checks of the GameCube files. No test was removed or skipped.
- **Classic Controller profiles match buttons by name**, like the GameCube ones: LB/RB → L/R, LT/RT → ZL/ZR, View → −, Menu → +.
- **Wii Remote layout:** D-pad and A on the left, larger 1 and 2 on the right, B top left (where the trigger is when the remote is held sideways), and −, Home, + in the middle. The Wii Remote controls are separate entries in the same saved layout, so existing saved layouts still load and each controller keeps its own positions. Show/Hide and Reset in the editor only touch the controller on screen. Switching controllers releases every button.
- **Tilt runs only in Wii Remote mode on the controller screen**, and pauses in the layout editor. When it stops, the phone sends one state without motion, so Dolphin reads zero motion instead of a frozen last reading.
- **Motion is kept out of the controller screen's own state.** `AppModel` combines the latest tilt with the last buttons, so 60 readings a second only redraw the small steering wheel.
- **No permission prompt:** `CMMotionManager`'s accelerometer and gyroscope need none, so `Info.plist` is unchanged.
- **Which way round the phone is held** is read from the window scene's interface orientation with every sample, so both landscape directions work.

## Unfinished or uncertain

- **Not run on a device or in Dolphin.** All of the mapping rests on reading Dolphin's source plus the tests above. Steering direction is the first thing to check (step 5 of the manual test).
- **The Wii Remote layout hasn't been looked at.** The Simulator keeps its data outside the project folder, so I didn't use it. I checked by calculation that no controls overlap on the smallest or a large iPhone. A screenshot on your phone is still worth a look.
- **No Nunchuk, and no upright (pointing) Wii Remote mode.** The Wii Remote layout is the sideways one, for steering games. The pointer is left to Dolphin's defaults.
- **While tilt is paused** (layout editor), Dolphin reads zero acceleration, which is what a remote in free fall would report. That only happens while editing.

## Safety rules: what this needed but I didn't do

- **Running the app in the Simulator** to look at the layout. Skipped, because the Simulator stores its data outside the project folder.
- **Reading your Dolphin settings on this Mac or running Dolphin** to check the profiles. Skipped (outside the folder). The profile keys are instead checked in tests against names taken from Dolphin's source on GitHub. I only read that source; nothing was saved outside the project or sent anywhere.
- **Build settings:** none changed; `project.yml` is untouched by this feature. For one check build for a real iPhone I passed `CODE_SIGNING_ALLOWED=NO` on the command line only.
- **Dependencies:** none added.
- **Build output:** I built with `-derivedDataPath DerivedData`, so Xcode wrote into `DerivedData/` inside the project (about 540 MB, already ignored by `.gitignore`). I didn't delete it, because you asked for no `rm -rf`. You can delete it whenever you like. Swift and Xcode may still have written their usual caches in your user Library, as any build does.

## For you to decide

- **The base commit `54cd51a` holds your earlier uncommitted work.** If you want that on `main` without the tilt feature, cherry-pick that one commit.
- **Whether to bump the protocol version** after all (see Decisions), if you'd rather have a clear "can't connect" than a silently ignored tilting phone with an old Mac app.
- **Whether to add a Nunchuk mode or an upright Wii Remote mode** later.

## Background: how input gets to Dolphin

1. `iOS/ControllerView.swift` keeps a `ControllerState` (buttons, two sticks, two triggers) and hands every change to `AppModel.send`. In Wii Remote mode, `AppModel` adds the latest tilt.
2. `ControllerLink` (MobiPadNetwork) seals it as `SessionMessage.state` and sends it over UDP, resent every 50 ms.
3. On the Mac, `ControllerHost` opens it and calls its output with `(slot, state)`.
4. `CompanionModel` passes it to `DSUServer.update(slot:state:)`, and to the keyboard output for Player 1.
5. `DSU.padData` builds the 100-byte cemuhook packet, now with the six motion fields filled from the state.
6. Dolphin's DSU client (`DualShockUDPClient.cpp`) reads that packet as device `DSUClient/<slot>/MobiPad`.

## Background: how Dolphin takes motion (Dolphin's source, master, 2026-10-03)

- The DSU client exposes `Accel Up/Down/Left/Right/Forward/Backward` (Up = −accel_y, Left = +accel_x, Forward = +accel_z, in g → m/s²) and `Gyro Pitch Up/Down`, `Roll Left/Right`, `Yaw Left/Right` (Pitch Up = +pitch, Roll Right = +roll, Yaw Right = +yaw, in °/s → rad/s).
- The emulated Wii Remote's `IMUAccelerometer` and `IMUGyroscope` groups (Motion Input) combine opposite directions (for example Up − Down) into Dolphin's frame: x = left, y = backward, z = up. When they're bound, Dolphin uses them instead of its simulated tilt.
- `Options/Sideways Wiimote` rotates the D-pad and the motion by a quarter turn around the remote's up axis.
- Wii Remote profiles live in `Config/Profiles/Wiimote/`. The extension is chosen with `Extension = None` or `Classic`, and the Classic Controller's keys are prefixed `Classic/`.
