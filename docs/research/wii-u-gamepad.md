# Research: the Wii U GamePad in MobiPad

*Status: researched, not started. Last updated 2026-10-10.*

## Summary

The phone can act as a Wii U GamePad in Cemu, in two levels:

1. **Controls and touch (cheap).** A "Wii U GamePad" layout that sends its buttons, sticks, motion and one touch point over the existing DSU route. Cemu already turns DSU touch into GamePad touchscreen input, so the Mac needs no mouse injection. Without the picture on the phone, though, you touch blind while watching Cemu's GamePad view on the Mac.
2. **The GamePad screen on the phone (real work).** The Mac captures Cemu's GamePad window, encodes it as video and streams it to the phone, which shows it under the controls. Touches land on the image itself. This is what makes it feel like a GamePad, and latency is the main risk.

A real Wii U GamePad on the Mac, or the phone acting as a GamePad for a real Wii U console, isn't feasible (see below).

Suggested order: try Cemu with the existing Classic Controller layout first (not done yet), then build level 1 on its own branch, then build a capture-and-stream prototype and measure its latency before committing to level 2.

## Level 1: controls and touch over DSU

### What Cemu does with DSU touch

Checked in Cemu's source (`main`, 2026-10-10):

- `DSUMessages.h`: each pad-data packet carries two touch points, `tpad1` and `tpad2`, each `{ uint8 active, uint8 index, int16 x, int16 y }`. They are the 12 bytes MobiPad now sends as zeros ("two inactive touches" in `DSUMessages.swift`). The separate `touch` byte before the sticks is the touchpad *button*; Cemu exposes it as a button called "Touch", not as a position.
- `DSUController::has_position()` is true while either touch point is active. `get_position()` takes `tpad1` (or else `tpad2`) and divides it by **1920 × 942**, the DualShock 4 touchpad's resolution, giving 0–1 coordinates.
- `VPADController::update_touch()` (the emulated GamePad) uses that position **before** falling back to the mouse on the GamePad view. It maps 0–1 straight onto the GamePad touchscreen (`x * 3883 + 92`, `4095 - y * 3694 - 254`), so 0–1 covers the whole GamePad picture.
- `EmulatedController::has_position()` is true if *any* controller bound to that emulated controller has a position. The DSU controller must therefore be bound to the emulated **Wii U GamePad**, and while the phone reports a touch, mouse clicks on the GamePad view are ignored.

The real GamePad screen is resistive and single-touch, so one touch point is enough.

### What MobiPad would need

- **A new phone kind**, `wiiUGamePad`, in landscape: two sticks, D-pad, A/B/X/Y, L/R/ZL/ZR, +/−, Home, and a touch area in the middle where the real pad has its screen (16:9, like the GamePad's 854 × 480). L3/R3 as on the other layouts.
- **Motion:** already sent over DSU. Cemu's `VPADController::update_motion` uses it, which covers gyro aiming (Splatoon, Breath of the Wild). The axes need checking for a phone held like a GamePad.
- **Wire format:** an optional touch point in `ControllerState` (normalized x and y, or nothing). Phone and Mac change in the same commit. An older Mac app should ignore it, as with motion.
- **DSU:** the Mac fills `tpad1` with `active = 1`, a touch index that goes up for each new touch, `x = u * 1920` and `y = v * 942`. Send touch only for the GamePad kind: Dolphin and Eden also read DSU touch (Eden passes it on as the Switch touchscreen), and the other layouts shouldn't start sending it by accident. `active` must drop to 0 on lift, or Cemu keeps touching and ignores the mouse.
- **Optionally "Set Up Cemu"**, like Set Up Dolphin and Set Up Eden, writing a GamePad profile for the DSU controller. Cemu's profile format and location on macOS haven't been checked yet.

Without the picture on the phone, level 1 suits menus and large buttons, with Cemu's GamePad view open on the Mac (Separate GamePad View, or both screens in one window). Precise touch (drawing, picking a spot on a map) needs level 2.

### Not available through DSU

- **Rumble:** Cemu's DSU client has none, and rumble was dropped from MobiPad on 2026-10-06 because of input lag anyway.
- **Camera, microphone and NFC:** DSU has no fields for them. Amiibo can be loaded from Cemu's own menu instead.
- **TV button:** has no use in an emulator.

### Players

A Wii U had one GamePad; a few games support two, and Cemu emulates at most two. The other players use a Wii U Pro Controller or a Wii Remote, which MobiPad's Classic Controller and Wii Remote layouts already cover.

## Level 2: the GamePad screen on the phone

Pipeline: Cemu's GamePad window → capture on the Mac → hardware encode → Wi-Fi → decode on the phone → show it under the controls → touches as 0–1 coordinates, as in level 1.

- **Capture:** ScreenCaptureKit can capture a single window (`SCContentFilter` for one window), with a set frame interval. Cemu shows the GamePad in its own window with Separate GamePad View. It needs the Screen Recording permission on the Mac (*from memory; Apple's docs page didn't load during this research*).
- **Encode and decode:** H.264 or HEVC through VideoToolbox, at about 854 × 480 and 60 fps, with low-latency rate control, no B-frames and frequent keyframes so a lost packet doesn't freeze the picture for long.
- **Transport:** the main piece of work. The current protocol sends small sealed UDP datagrams, one per state. Video needs its own channel so it can't delay input: frames split over several packets, a way to recover from loss (ask for a keyframe, or drop to the next one), and encryption like the existing `SecureChannel`.
- **Touch mapping:** the phone knows where the video sits on its screen, so it converts a touch into 0–1 coordinates on the picture and sends them as in level 1.

### Risks

- **Latency.** Capture, encode, Wi-Fi and decode add a chain the controls don't have. My estimate is a few tens of milliseconds (*unverified*). That's acceptable for the second screen, as long as button input isn't delayed by it. A prototype should measure glass-to-glass latency on a home network before more is built. Rumble was dropped for lag, so this deserves a hard number up front.
- **Network.** Same as the controls: client isolation (the UU Wi-Fi) blocks it, a home network or the iPhone's Personal Hotspot works. A video stream needs much more bandwidth than input (*inferred*: a few Mbit/s).
- **Battery and heat** on the phone from constant decoding and a bright screen (*inferred*).
- **Size.** Level 2 touches both apps, the protocol and a new Mac permission. It's a large task in the sense of the global instructions: several sessions, with progress notes.

## Not feasible

- **A real Wii U GamePad on the Mac.** The GamePad talks to the console over a modified 5 GHz Wi-Fi link (its own pairing and a video stream). The community projects that use it on a PC, libdrc and drc-sim, need Linux, a specific Wi-Fi chip and a patched wpa_supplicant. That doesn't fit a Mac app.
- **The phone as a GamePad for a real Wii U console.** It runs into the same link, and iOS gives no low-level Wi-Fi access (*inferred*).

## Open questions

1. Does Cemu work with MobiPad at all on this Mac (Classic Controller layout over DSU)? Not tried yet.
2. Cemu's controller profile format and location on macOS, for a possible Set Up Cemu.
3. Which games to target, so the touch and gyro needs are concrete.
4. Glass-to-glass latency of a capture-and-stream prototype.

## Sources

- Cemu source, [`DSUController.cpp`](https://github.com/cemu-project/Cemu/blob/main/src/input/api/DSU/DSUController.cpp) and [`DSUMessages.h`](https://github.com/cemu-project/Cemu/blob/main/src/input/api/DSU/DSUMessages.h): DSU touch points read as a position, scaled by 1920 × 942.
- Cemu source, [`VPADController.cpp`](https://github.com/cemu-project/Cemu/blob/main/src/input/emulated/VPADController.cpp): `update_touch()` prefers the controller position over the mouse; `update_motion()`.
- Cemu source, [`EmulatedController.cpp`](https://github.com/cemu-project/Cemu/blob/main/src/input/emulated/EmulatedController.cpp): any bound controller with a position supplies touch.
- libretro docs, [Nintendo - Wii U (Cemu)](https://docs.libretro.com/library/cemu/): separate GamePad view, the mouse as touchscreen.
- PCGamesN, [Wii U GamePad reverse engineered for PC streaming](https://pcgamesn.com/wii-u-gamepad-reverse-engineered-pc-streaming), and the [LKML thread on a Wii U DRC driver](https://lkml.iu.edu/hypermail/linux/kernel/2105.0/04697.html): what using a real GamePad on a PC takes.
- [drc-sim packages](https://packagecloud.io/rolandoislas/drc-sim/packages/ubuntu/xenial/wpasupplicant-drc_2.1-devel_amd64.deb): the patched wpa_supplicant drc-sim needs.
- Apple docs, [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).
