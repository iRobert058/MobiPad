# Research: virtual gamepad on macOS (DR-04)

*Status: decided, see below. Last updated 2026-09-30.*

## Decision (2026-09-30)

**We are not using Core HID.** There is no paid Apple Developer Program membership and none is planned, so the entitlement it needs can't be obtained. The MVP targets are emulators: **Mario Kart Wii in Dolphin**, plus one more emulator still to be named. Emulators give us two routes that need no entitlement:

1. **DSU server (primary).** Dolphin has a built-in DSU client, which uses the "cemuhook" protocol, under *Alternate Input Sources*. Through it, Dolphin receives buttons, analog sticks, analog triggers, touch, accelerometer and gyroscope over UDP. The Mac companion app runs a DSU server on `127.0.0.1:26760`, so Dolphin is set up once and never needs the phone's IP address. Because motion data comes along, the iPhone can also work as a **Wii Wheel** (tilt to steer).
2. **Keyboard output (fallback)** for emulators without DSU. It posts keyboard events with `CGEvent`, which needs the Accessibility permission (granted locally, no account). Sticks become digital.

Architecture: `iPhone → Wi-Fi → Mac companion → DSU server (localhost) or keyboard events → emulator`.

No special test machine is needed: both routes work on a normal Mac with SIP on.

**Second emulator (Cemu or Ryujinx, checked against their source and docs on 2026-09-30):**
- **Cemu** (Wii U) has a full DSU controller API ("DSUController": buttons, sticks, triggers, motion), built on every platform, macOS included. It reads buttons from the DSU bitmask bytes, while Dolphin reads the analog pressure bytes; MobiPad fills both.
- **Ryujinx** (Switch): its docs list SDL gamepads and the keyboard as input devices, with no DSU option. As far as I know its "CemuHook" support covers motion only, but I couldn't confirm that in its source, because the repository has moved since the original project ended. MobiPad therefore feeds Ryujinx through the keyboard route, for Player 1.

Caveat: Dolphin labels DSU buttons with PlayStation names (Cross, Circle, Square, Triangle). Mapping them is a one-time step in Dolphin's controller settings, and MobiPad could ship a ready-made Dolphin profile.

The findings below are kept for reference, in case Core HID becomes an option later (for example, if Apple adds a development variant of the entitlement).

## Summary

- **Use Core HID's `HIDVirtualDevice`** (macOS 15+). Apple DTS recommends it over DriverKit: both use the same kernel path, and Core HID is a plain user-space Swift API.
- **It needs a restricted entitlement,** `com.apple.developer.hid.virtual.device`. Apple grants it on request, only to paid Apple Developer Program members. One developer reported waiting more than 2.5 months in 2026. **Submit the request now**, because the MVP can't ship without it.
- **The entitlement has no development variant yet.** Until Apple approves the request, a virtual device can only be tested on a Mac with SIP and AMFI disabled. That should be a dedicated test machine, not a daily one.
- **The biggest open risk is whether games see the device.** Apple says the GameController framework has *"existing checks … to ignore virtual HID devices"*. SDL skips devices that the GameController framework claims, so an imitation Xbox or DualSense controller could end up invisible to both. A short spike (below) has to settle this before we build the rest of the desktop app.
- **Fallback that works today without any entitlement:** send keyboard and mouse events with `CGEvent`. It isn't a gamepad, but it works in games that accept keyboard input.

## Options compared

| Option | Seen as a gamepad by games? | Permission needed | Effort | Verdict |
|---|---|---|---|---|
| **Core HID `HIDVirtualDevice`** | Yes for HID/SDL-based input. GameController framework uncertain (see below) | `com.apple.developer.hid.virtual.device` (restricted, on request) | Low | **Primary** |
| DriverKit HID driver (dext) | Same as Core HID: Apple says they "work in EXACTLY the same way" | DriverKit HID entitlements (on request) + the user approves a system extension | High | No, more work for no benefit |
| Keyboard/mouse events via `CGEvent` | No, keyboard and mouse only | Accessibility permission | Low | Fallback only |
| Kernel extension (e.g. foohid) | n/a | Kexts are deprecated; foohid is unmaintained | n/a | No |
| iPhone as Bluetooth HID gamepad (no desktop app) | n/a | iOS doesn't let apps advertise the HID-over-GATT service | n/a | Not possible |
| `GCVirtualController` | Only inside your own app; it draws on-screen controls and doesn't create a system-wide device | n/a | n/a | Not applicable |

## How macOS games read controllers

This decides which **identity** the virtual device should present.

- **GameController framework** (native Mac games, Apple Arcade): recognises known hardware such as Xbox, PlayStation and MFi controllers by "specific (undocumented) hardware details". It deliberately ignores some virtual HID devices to avoid input loops. Apple DTS: *"I think CoreHID will work fine, but it's possible there's some detail I've overlooked that would interfere with GameController matching."*
- **SDL** (many Steam ports and emulators): reads IOKit HID devices with a Joystick, GamePad or MultiAxisController usage, **but skips any device the GameController framework says it supports**. SDL's reasoning is to "prefer Game Controller support where available".
- **Browsers** (Gamepad API) and **Steam** read HID devices themselves.

That leaves two identity strategies:

| | A. Imitate a known controller (Xbox / DualSense VID/PID + its exact report format) | B. Our own generic gamepad (own VID/PID, standard HID gamepad descriptor) |
|---|---|---|
| Best case | Works everywhere, including GameController-only games | SDL, browsers and Steam see it |
| Worst case | GameController ignores it as virtual **and** SDL skips it as GameController-supported, so no game sees it | GameController-only games never see it |
| Extra work | Reproduce the vendor's exact report protocol. Using another vendor's IDs raises a legal/trademark question to settle before release | SDL needs a mapping: contribute one to SDL's controller database or ship it through Steam's configuration |

**Recommendation (if Core HID is ever used):** build on B and test A in the spike. A first Core HID implementation of B (report descriptor, encoder, `HIDVirtualDevice` wrapper) was written but removed before it was ever committed, so it would have to be rewritten. [JoyCon2Mac](https://github.com/OZORDI/JoyCon2Mac) reports that a virtual DualSense works with GameController clients and SDL. It uses DriverKit on machines with SIP disabled, though, so that doesn't prove the same holds for Core HID.

## Spike plan

**Goal:** find out which identity real games recognise. **Timebox:** 2–3 days once a test machine is ready.

1. Prepare a test Mac with SIP and AMFI disabled, or wait for the entitlement.
2. Create each variant of the virtual device:
   identity (generic / DualSense / Xbox) × transport (`.virtual` / `.usb` / `.bluetooth`).
3. For each variant, check:
   - the device appears in `hidutil list`
   - `GCController.controllers()` reports it (small test app)
   - SDL3 `testcontroller` sees it as a gamepad
   - a browser gamepad test page sees it (Safari and Chrome)
   - Steam's controller settings see it
   - the 2–3 target games respond (these still need to be chosen, see open questions)
4. Write the outcome back into this document.

**Done when:** at least one variant works in all target games, or we know which games can't be supported.

## Impact on the requirements

- **DR-01:** the minimum macOS version becomes **macOS 15 Sequoia**, because Core HID requires it.
- **Distribution:** the app needs a paid Developer Program membership, Developer ID signing and notarisation. The Mac App Store is unclear. Apple DTS says apps that need the Accessibility permission are generally not eligible, but that prompt applies to virtual keyboards, mice and touchpads, not gamepads. A gamepad-only device may therefore avoid it (unverified).
- **FR-07 / MVP acceptance:** "fully control a game" needs a concrete list of target games to test against.
- **Planning:** the entitlement wait is on the critical path for DR-04, but the iPhone app, networking and the desktop test screen (FR-08) can go ahead without it.

## Open questions

1. ~~Paid Apple Developer Program?~~ No, and none planned.
2. ~~Test Mac with SIP and AMFI disabled?~~ No, and no longer needed.
3. ~~Target games?~~ Mario Kart Wii (Dolphin), plus Cemu or Ryujinx. Both are covered: Cemu through DSU, Ryujinx through the keyboard.
4. ~~Imitating Xbox/DualSense?~~ Moot without Core HID.

## Sources

- Dolphin source, [`DualShockUDPClient.cpp`](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/InputCommon/ControllerInterface/DualShockUDPClient/DualShockUDPClient.cpp): the inputs Dolphin's DSU client exposes, and its server configuration.
- Cemu source, [`DSUController.cpp`](https://github.com/cemu-project/Cemu/blob/main/src/input/api/DSU/DSUController.cpp) and [`src/input/CMakeLists.txt`](https://github.com/cemu-project/Cemu/blob/main/src/input/CMakeLists.txt): Cemu's DSU input and its build on all platforms.
- Dolphin forums, [cemuhook DSU protocol doesn't see GameCube buttons](https://forums.dolphin-emu.org/Thread-cemuhook-dsu-protocol-doesn-t-see-gamecube-buttons): DSU buttons show up under PlayStation names.
- Apple DTS, [Supported way to expose an iPhone+controller as a macOS gamepad without restricted entitlements?](https://developer.apple.com/forums/thread/820708) (Mar 2026): entitlement is required, Core HID recommended, CGEventTap as fallback, no development variant yet (r.173531752).
- Apple DTS, [Which virtual-HID entitlement path for a gamepad app — CoreHID or DriverKit?](https://developer.apple.com/forums/thread/845599) (2026): Core HID and DriverKit are architecturally identical; approval delays; GameController matching uncertain.
- Apple DTS, [HID Entitlement Configuration Guide](https://developer.apple.com/forums/thread/843327) (Aug 2026): which entitlement goes where.
- Apple DTS, [Does using HIDVirtualDevice rule out Mac App Store distribution?](https://developer.apple.com/forums/thread/822647) (Apr 2026): the Accessibility prompt is tied to keyboard, mouse and touchpad devices.
- Apple Frameworks Engineer, [Virtual Controllers on Mac via the Game Controller Framework](https://developer.apple.com/forums/thread/812774) (Jan 2026): GameController ignores some virtual HID devices.
- Apple docs, [`HIDVirtualDevice`](https://developer.apple.com/documentation/corehid/hidvirtualdevice) (macOS 15+). The API was also verified against the local SDK's `CoreHID.swiftinterface`.
- SDL source, [`SDL_iokitjoystick.c`](https://github.com/libsdl-org/SDL/blob/main/src/joystick/darwin/SDL_iokitjoystick.c), and the commit [Clarify why we're skipping Game Controller framework supported devices](https://discourse.libsdl.org/t/sdl-clarify-why-were-skipping-game-controller-framework-supported-devices-in-hid-c/31725).
- [JoyCon2Mac](https://github.com/OZORDI/JoyCon2Mac): a DriverKit virtual DualSense on macOS (needs SIP and AMFI disabled).
