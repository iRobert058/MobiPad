# Tilt controls: notes

Branch: `tilt-controls`, made from `main` on 2026-10-03. Nothing is pushed or merged, and `main` is untouched.

## Progress

- **Done:** the original eight steps; the pointer work; after the live tests: Dolphin's gyroscope calibration off, Point's Accelerometer Influence off, buttons that always count a completed tap, the pointing Wii Remote held upright like a real remote, and taps held for at least 120 ms.
- **Working on:** nothing. Merged into `main` on 2026-10-03, after the upright pointing remote and quick A taps worked in the Wii Menu.
- **Next step:** none. Mario Kart steering was checked on 2026-10-06 and works.
- **Half-finished or broken:** nothing known.

## Fourth live test (2026-10-06)

- **Mario Kart Wii steering works,** with the phone held sideways.
- **The 2 button didn't register with a thumb only partly on it.** Every button's touch area now reaches past its circle, on branch `rumble`.
- **Rumble was asked for.** See Rumble in the README.

## Third live test (2026-10-03)

Measured with a small script on the Mac that subscribes to MobiPad's DSU server the way Dolphin does, and logs every A press and the motion it carries.

- **Dolphin had kept the old settings.** The profile on disk was written by an older Mac build, and Dolphin's active Wii Remote settings had neither fix. After Set Up Dolphin and loading the profile again, both were active.
- **Up and down: the phone was held like a TV remote,** in one hand with its left end toward the TV. Pointing up and down then turns the phone around its own top edge, which Dolphin, told that the top edge points at the TV, reads as twisting the remote; left and right work either way. Held flat in both hands with the top edge toward the TV, up and down worked perfectly. You preferred the remote grip, so the pointing remote now turns the screen upright and is held like a real Wii Remote, top toward the TV. Upright, the phone's own axes already are the remote's, so the motion goes out unturned.
- **A: every tap reached Dolphin, but the Wii Menu ignored the short ones.** All 44 taps of the first round arrived at the DSU port, 41 of them exactly 50 ms long (the minimum the button held them for; iOS delivered them only when the thumb lifted). Quick taps: none of 5 registered, all 30–60 ms. Half-second holds: all 5 registered, 375–661 ms. Dolphin reads the Wii Remote 200 times a second (`BTEmu.cpp`), so it saw the short ones too; it's the game that wants a longer press. Three earlier presses of 90–121 ms seem to be the three that registered. The minimum press is now 120 ms, about as long as a real quick tap.
- **Changes:** `ControllerKind.isUpright` and an app delegate that turns the screen (portrait added to the supported orientations in `project.yml`, which the feature needs); `Motion.Orientation` with a `portrait` case (was `Landscape`); a new upright pointing layout, with old landscape placements of the pointing controls reset once; `PressableButton.minimumPress` 50 → 120 ms.
- **Afterwards:** the start screen also turns upright when the phone does (it follows the phone; the controller screens keep their fixed orientation).

## Second live test (2026-10-03)

- **Better, but up and down still worse than left and right, and A sometimes doesn't register.**
- **Cause of up and down, by simulation** (Dolphin's pointer code ported, fed realistic wrist movement): Dolphin pulls up/down, but not left/right, toward the accelerometer ("Accelerometer Influence", 2%). The accelerometer also feels the phone's own movement, which Dolphin takes for tilt. With quick flicks and the phone tilted 35° toward you, up/down was off by 5.1° on average (8.5° worst) after pressing Center. With the influence at 0% it's 0.4°, the same as left/right. Sending gravity without the movement fixed it equally well, but would also hide small motions from games, so I chose the profile setting.
- **Likely cause of missed A presses:** a thumb pushing the screen is the same kind of movement. At 2% a firm tap jumped the pointer up or down by about 2° (roughly 150 pixels on a TV), enough to slide off a button just as A was pressed. At 0% it doesn't move.
- **Also:** on the right half of this iPhone's screen, iOS can hold back a lone tap and deliver its start and end together (see the earlier touch-delay finding). The button now counts a press when the touch ends even if it never reported a change, so such a tap can't get lost.
- **Changes:** `IMUIR/Accelerometer Influence = 0` in the Wii Remote profile; `PressableButton` presses on `onEnded` as well.

## First live test (2026-10-03)

- **The pointer works**, and left and right are good.
- **Drift to the left while still, gone after reconnecting.** Most likely Dolphin's gyroscope calibration: when the phone connects, Dolphin takes its first gyroscope reading as zero (`IMUGyroscope::UpdateCalibration`) and only replaces it after 3 seconds of near-perfect stillness. If the phone moved at that moment, the pointer drifts. iOS already removes the gyroscope's offset, so the profile now sets `IMUGyroscope/Calibration Period = 0`.
- **Open: vertical pointer.** You described up and down as "a disaster". I ported Dolphin's pointer code and simulated it with MobiPad's data: a still, tilted phone settles within a second, and MobiPad's accelerometer and gyroscope agree with each other in Dolphin's frame. So it isn't a simple sign error in what MobiPad sends. Candidates, to tell apart in the next test:
  - a bad calibration on the up/down axis (fixed by the change above, if that was it);
  - Dolphin's accelerometer correction ("Accelerometer Influence", 2%) pulling the pointer up or down while the phone moves;
  - the way the phone is held: Dolphin aims along the phone's top edge, so held upright like a camera, up and down behave badly.

## What you get

- On the phone, choose **Classic Controller** (today's layout, no motion), **Wii Remote (sideways)** (steering, Mario Kart) or **Wii Remote (pointing)** (pointer games like Wii Party). Choose on the start screen, or with the menu next to Edit Layout on the controller screen, also mid-game.
- In both Wii Remote modes the phone reads its accelerometer and gyroscope 100 times a second and sends them with the buttons. Sideways, a steering wheel next to the player name turns as you tilt. Both Wii Remote layouts have a **Center** button that recenters Dolphin's pointer. The Mac menu shows a moving tilt dot per player.
- **Set Up Dolphin** in the Mac menu now also writes, per player, **MobiPad Wii Remote Player N** (buttons, D-pad, accelerometer, gyroscope, Center → pointer recenter; one profile for both holds) and **MobiPad Classic Player N** (a Wii Remote with the Classic Controller extension). The GameCube profiles are unchanged.
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
10. `a650ed8`: README, these notes, and two small fixes in the iPhone code: one shared motion manager, and the last sent buttons cleared on connect and disconnect.
11. `8440170`: the phone turns its motion and D-pad sideways itself instead of Dolphin, so one profile serves every hold.
12. `5a83ffb`: the Center button recenters Dolphin's pointer.
13. `f1f3aca`: the Wii Remote (pointing) layout, and motion at 100 Hz.
14. The last commit: README and these notes for the pointer work.

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
   - Options shows **Sideways Wii Remote** *not* ticked (the phone turns its motion itself).
   - The **Motion Input** tab shows Accelerometer and Gyroscope mapped to `Accel …` and `Gyro …`, Point's Recenter mapped to `R3`, and its previews move when you tilt the phone.
4. On the phone choose **Wii Remote (sideways)**. The steering wheel by your name should turn as you tilt, and the tilt dot in the Mac menu should move.
5. In Mario Kart Wii, play with the **Wii Wheel / sideways Wii Remote** controls, holding the phone like a steering wheel with the screen toward you:
   - Turning the phone clockwise should steer **right**. If it steers left, tell me: that would mean a sign is flipped, which is a one-line fix in `DSU.motionFields`.
   - Do the same with the phone turned the other way round (camera on the other side). Steering should still be correct.
   - Buttons: 2 accelerates, 1 brakes, B drifts, the D-pad uses items, + pauses.
   - Shake the phone for tricks and wheelies.
   - Menus: try navigating with the D-pad. Dolphin may also move the pointer with the phone's motion ("Point" under Motion Input); note whether that gets in the way.
6. **Pointing (Wii Party):** switch the phone to **Wii Remote (pointing)**; the screen turns upright. Hold it like a Wii Remote, screen up, top toward the TV. In the Wii Menu or Wii Party:
   - Aim at the middle of the TV and tap **Center**. The pointer should follow the phone smoothly, up/down and left/right in the right directions, and A should select.
   - If it moves too fast or too slow across the screen, try **Total Yaw** under Point in Dolphin (default 25°), and tell me what feels right; I can put it in the profile.
   - Try a motion minigame (a shake or a twist) to check the remote's orientation feels right while pointing.
   - Switch between sideways and pointing in the middle of a game; Dolphin needs no change.
7. With the phone on **Classic Controller**, load **MobiPad Classic Player 1** in Dolphin and try a Wii game that supports the Classic Controller (Mario Kart Wii does).
8. Check that nothing else changed: the GameCube profile in Dolphin, Cemu, and Ryujinx with "Player 1 as keyboard", all with the phone on Classic Controller.
9. On the phone: Edit Layout in both Wii Remote modes (tilt should pause while editing), switching controllers while connected, and battery and heat after a long session with tilt.
10. With your friend: a phone with yesterday's build should still work with the new Mac app on the Classic Controller layout.

## Decisions

- **The phone turns its motion sideways itself, and Dolphin's "Sideways Wii Remote" option stays off.** At first the profile switched that option on and let Dolphin turn the motion and D-pad. That broke pointer games like Wii Party, where the remote is held upright: Dolphin's option would turn the motion for those too, and changing it means editing the profile. Now the phone does the same quarter turn (`Motion.turnedSideways`, checked in a test against Dolphin's `GetOrientation`) only in the sideways layout, and the sideways D-pad sends the turned directions. One profile serves every hold, and the player can switch holds mid-game.
- **Pointing uses Dolphin's gyroscope pointer** ("Point" under Motion Input, `IMUIR`, on by default on the Mac). It follows the gyroscope relative to where it started; left and right are limited to Total Yaw (25°). The phone is held upright with its top toward the TV, like a real remote, which is how Dolphin aims a controller that isn't turned sideways (see "Third live test").
- **Center sends R3**, which neither Wii Remote layout uses otherwise, and the profile maps it to `IMUIR/Recenter`.
- **Wii Remote (pointing) layout, upright:** top to bottom as on the remote: the D-pad, A big under the thumb, B below it (the trigger behind A on the remote), −, Home, +, then 1 and 2. Center sits next to B, in reach of the thumb.
- **Motion at 100 Hz** instead of 60, for a smoother pointer. That's 100 small packets a second per phone in the Wii Remote modes; Classic Controller is unchanged.
- **The Mac menu shows a tilt dot instead of a turning wheel,** because the motion it receives is turned sideways in one mode and not in the other; a level bubble reads right either way. The phone's own steering wheel works from its unturned readings.
- **Frame of `Motion`:** x points to the right edge of the screen as the player holds it, y to the top edge, z out of the screen. Acceleration is what an accelerometer measures (+1 g on z when lying face up); rotation follows the right-hand rule, in °/s.
- **Mapping to Dolphin** (from `DualShockUDPClient.cpp`): accelerometer x = left (−x), y = −up (−z), z = forward (+y); gyro pitch = +x, yaw = −z, roll = +y. The Wii Remote profile maps each `IMUAccelerometer`/`IMUGyroscope` direction to the DSU input of the same name, as Dolphin's own defaults do. `DSUMotionTests` read the packet the way Dolphin does, including its Sideways rotation.
- **Motion travels inside the state snapshot** as an optional block, not as a separate message. One packet keeps carrying everything, and the DSU packet already had the fields.
- **The protocol version stays at 3.** Phones without tilt send the same 16 bytes as before, so a phone with an older build keeps working with the new Mac app. Only a tilting phone needs the new Mac app. The alternative, bumping the version, would have locked older phones out entirely.
- **Wii Remote buttons reuse the existing state buttons** (in both Wii Remote layouts): A → A, B → B, 1 → X, 2 → Y, − → View, + → Menu, Home → Home (over DSU: Cross, Circle, Square, Triangle, Share, Options, PS). The Wii Remote profile maps them back, so the wire format and the Mac side needed no new buttons.
- **Set Up Dolphin writes all three profile kinds at once**, so there's still one button. Two existing tests listed exactly the four GameCube profile names in the outcome. I updated those two expectations to the full list of twelve and kept their checks of the GameCube files. No test was removed or skipped.
- **Classic Controller profiles match buttons by name**, like the GameCube ones: LB/RB → L/R, LT/RT → ZL/ZR, View → −, Menu → +.
- **Wii Remote layout:** D-pad and A on the left, larger 1 and 2 on the right, B top left (where the trigger is when the remote is held sideways), and −, Home, + in the middle. The Wii Remote controls are separate entries in the same saved layout, so existing saved layouts still load and each controller keeps its own positions. Show/Hide and Reset in the editor only touch the controller on screen. Switching controllers releases every button.
- **Motion runs only in the Wii Remote modes on the controller screen**, and pauses in the layout editor. When it stops, the phone sends one state without motion, so Dolphin reads zero motion instead of a frozen last reading.
- **Motion is kept out of the controller screen's own state.** `AppModel` combines the latest tilt with the last buttons, so 60 readings a second only redraw the small steering wheel.
- **No permission prompt:** `CMMotionManager`'s accelerometer and gyroscope need none, so `Info.plist` is unchanged.
- **Which way round the phone is held** is read from the window scene's interface orientation with every sample, so both landscape directions work.

## Unfinished or uncertain

- **Run on a device and in Dolphin since.** Steering direction was confirmed in Mario Kart Wii on 2026-10-06.
- **Layouts:** overnight I didn't use the Simulator (your folder rule). Afterwards, with you back, I checked both Wii Remote layouts in the Simulator, and by calculation that no controls overlap on the smallest or a large iPhone.
- **No Nunchuk.** Wii Party doesn't need one, but some games do.
- **The pointer's feel is untested.** Total Yaw and Dolphin's other Point settings are left at their defaults until you've tried it.
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
- **Whether to add a Nunchuk** later.

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
- `Options/Sideways Wiimote` rotates the D-pad and the motion by a quarter turn around the remote's up axis. MobiPad leaves it off and does the same turn on the phone.
- The gyroscope pointer (`IMUIR`) is on by default on the Mac and has a Recenter input. It works from the gyroscope without any sideways turn applied.
- Wii Remote profiles live in `Config/Profiles/Wiimote/`. The extension is chosen with `Extension = None` or `Classic`, and the Classic Controller's keys are prefixed `Classic/`.
