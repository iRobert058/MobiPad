# MobiPad

Use an iPhone as a wireless game controller for emulators on a Mac. Up to four phones can play at once. See [requirements.md](requirements.md).

```
iPhone ──Wi-Fi (encrypted UDP, Bonjour)──▶ Mac companion app ──▶ DSU on localhost ──▶ Dolphin, Cemu
                                                            └──▶ key presses ───────▶ Ryujinx (Player 1)
```

MobiPad doesn't create a system-wide virtual gamepad, because that needs a paid Apple entitlement. Emulators read it as a DSU controller, or as a keyboard. [docs/research/virtual-hid-macos.md](docs/research/virtual-hid-macos.md) explains why.

## Layout

```
MobiPadKit/            Swift package with all the logic, testable without Xcode
  MobiPadProtocol      controller state, message format, encryption (SecureChannel)
  MobiPadNetwork       phone side (ControllerLink, MacBrowser) and Mac side (ControllerHost)
  MobiPadDSU           DSU server that Dolphin and Cemu connect to
  MobiPadKeyboard      Player 1 as key presses, for Ryujinx
iOS/                   iPhone app: name, find a Mac, then the controller
macOS/                 Mac menu bar app: approvals, player slots, latency, live input
docs/research/         technical research and decisions
project.yml            XcodeGen spec that generates MobiPad.xcodeproj
```

## Running it

You need Xcode (free, from the Mac App Store) and your Apple ID. A paid developer account isn't needed.

1. Generate the Xcode project:
   ```sh
   brew install xcodegen
   xcodegen generate
   open MobiPad.xcodeproj
   ```
2. In Xcode → Settings → Accounts, sign in with your Apple ID. That creates a free "Personal Team". Put its team ID in `project.yml` under `DEVELOPMENT_TEAM`, then run `xcodegen generate` again.
3. Run the **MobiPadCompanion** scheme. A controller icon appears in the menu bar. Allow local network access when macOS asks.
4. Connect your iPhone by cable, turn on Developer Mode on it (Settings → Privacy & Security), and run the **MobiPad** scheme on it. The first time, the iPhone won't open the app ("Untrusted Developer"): go to Settings → General → VPN & Device Management, tap your Apple ID under Developer App, and tap Trust. Apps from a free account stop working after 7 days; running them again from Xcode renews them.

   To try the iPhone app without a phone, run the **MobiPad** scheme on an iPhone Simulator instead. It finds the Mac app the same way. Turn the Simulator to landscape with ⌘→.
5. In the iPhone app, type your name and pick your Mac. The first time, the Mac asks **"Allow … to connect?"**. After you click Allow, the phone shows up as a player and is remembered from then on.

### Changing the controller layout

Tap **Edit Layout** at the top of the controller screen. Drag a control to move it, and pinch it to resize it. For a small button, tap it and use the slider, or pinch on an empty part of the screen. **Show/Hide** turns controls on and off, including L3, R3 and Home, which start off. The D-pad and A/B/X/Y move as one block each. **Done** saves the layout on the phone, **Cancel** throws the changes away, and **Reset** goes back to the standard layout.

### Checking an emulator without a phone

Turn on **Test controller** in the Mac menu. It joins as a player that circles its sticks and presses A, B, X and Y in turn. In the emulator's controller settings, the DSU device's inputs should move (for Ryujinx: with the keyboard toggle on and the test controller as Player 1, keys get pressed). If that works but the phone doesn't, the problem is between the phone and the Mac. Turn the test controller off before mapping buttons, or it presses buttons while the emulator waits for yours.

### Dolphin (Mario Kart Wii)

1. Controllers → **Alternate Input Sources** → enable **DSU Client** and add a server: IP `127.0.0.1`, port `26760`.
2. Configure the emulated controller (a GameCube controller or a Classic Controller works well for Mario Kart Wii). Pick the DSU device, then map each input by clicking it and pressing the matching button on the phone.
   Dolphin uses PlayStation names: **Cross = A, Circle = B, Square = X, Triangle = Y, L1/R1 = LB/RB, L2/R2 = LT/RT**.
3. For more players, repeat step 2 for port 2, 3 or 4 and pick DSU device 1, 2 or 3.

### Cemu

In Input settings, choose the **DSUController** API, point it at `127.0.0.1`, port `26760`, and pick the controller for each player. Cemu reads the same DSU data as Dolphin.

### Ryujinx

Ryujinx can't read DSU input (see the research doc), so MobiPad sends Player 1 as key presses:

1. In the Mac menu, turn on **Player 1 as keyboard**. The first time, macOS asks you to allow MobiPad under Privacy & Security → Accessibility. Do that, then turn the toggle on again.
2. In Ryujinx, use the keyboard as Player 1's input device. MobiPad presses Ryujinx's default keys, matched by button position:

   | Phone | Key | | Phone | Key |
   |---|---|---|---|---|
   | A (bottom) | X | | Left stick | W A S D |
   | B (right) | Z | | Right stick | I J K L |
   | X (left) | V | | D-pad | arrow keys |
   | Y (top) | C | | LB / RB | E / U |
   | Menu | = | | LT / RT | Q / O |
   | View | − | | L3 / R3 | F / H |

   If a button does nothing, rebind it in Ryujinx by pressing the phone button while Ryujinx waits for a key.

Only turn the keyboard toggle on while playing: Player 1's buttons type into whichever app is in front. Rebuilding the Mac app with a free account can reset the Accessibility permission, so you may need to allow it again.

## Security

A phone has to be allowed on the Mac once (CR-03). After that, all input is encrypted and authenticated (NFR-06). Every phone has its own key, and the Mac only accepts input from the phone holding that key, so a device that copies a phone's details still can't send input or take its slot. **Forget** in the menu removes every approved phone.

Not covered: the phone doesn't check that it's talking to the real Mac. A fake Mac on your network could see your button presses, but it can't control anything.

## Debugging

- **Mac menu:** shows each player's name, latency and live sticks and buttons. The test controller (above) separates emulator problems from phone problems.
- **Log:** phones joining, leaving, timing out and asking for approval, and emulators subscribing, all under subsystem `MobiPad` (categories `host`, `link`, `dsu`). They're saved, so you can read them after the fact. In Console.app, search for `subsystem:MobiPad`. In Terminal:
  ```sh
  /usr/bin/log show --last 30m --predicate 'subsystem == "MobiPad"' --style compact
  ```
  Use the full path `/usr/bin/log`: zsh has its own `log` command. For the iPhone's side, connect it to the Mac and select it in Console.app.

## Tests

```sh
cd MobiPadKit && swift test
```

The tests include real UDP round-trips on localhost:
- approvals, and four phones plus a fifth that waits
- the test controller taking a free slot
- reconnecting, timeouts and latency
- an impostor with a copied public key
- a button press travelling all the way to a Dolphin-style DSU client

With only the Command Line Tools installed (no Xcode), point `swift test` at Swift Testing:

```sh
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $FW -Xlinker -F -Xlinker $FW \
  -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

## Status

Done, and tested in the package:
- **Connecting (FR-01, FR-02, CR-01, CR-02):** Bonjour discovery, connecting and disconnecting.
- **Pairing and encryption (CR-03, NFR-06).**
- **Streaming input (FR-06, NFR-01):** full snapshots on every change, resent every 50 ms, and old packets dropped.
- **Up to four players (FR-10)**, each keeping their player number across dropouts.
- **Automatic reconnect (FR-09)** and **latency (DR-03)**.
- **DSU for Dolphin and Cemu.**
- **Keyboard key mapping for Ryujinx.**
- **Test controller in the Mac menu.**

Checked on this Mac without Xcode:
- `project.yml` generates a valid Xcode project (app IDs, OS versions, package links).
- The Mac app's code builds and runs. Started as a plain executable, its DSU server answered a Dolphin-style request (checksums verified with Python's zlib), it advertised itself over Bonjour as "Robert's MacBook Pro", and it wrote its log.

Written, but not yet run on a device or in an emulator (the apps haven't been built yet):
- iPhone layout (FR-03, UX-02), with LB/RB/LT/RT added for Mario Kart
- multi-touch (FR-04) and haptics (FR-05)
- layout editing (UX-03): checked in the Simulator that it draws correctly, but moving and resizing by touch haven't been tried
- the Mac's menu: approval prompt, test screen (FR-08), test controller switch and keyboard output

Not planned for now: tilt steering.
