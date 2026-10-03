# MobiPad

Use an iPhone as a wireless game controller for emulators on a Mac. Up to four phones can play at once. See [requirements.md](requirements.md) (in Dutch).

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
Shared/AppIcon.icon    app icon for both apps, with light, dark and clear/tinted versions; open it in Icon Composer (comes with Xcode) to edit
Shared/mobipad-app-icon/  the icon's source layers per mode, alternatives and previews
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

### Classic Controller or a Wii Remote

Choose the controller on the start screen, or with the menu next to **Edit Layout** on the controller screen:

- **Classic Controller:** two sticks, A/B/X/Y, shoulder buttons and triggers. Works with every emulator, as before.
- **Wii Remote (sideways):** held like a steering wheel or an NES pad, screen toward you. Tilting the phone steers, as in Mario Kart Wii. The steering wheel next to the player name turns as you tilt, so you can see tilt is working.
- **Wii Remote (pointing):** for pointer games like Wii Party and the Wii Menu. Hold the phone flat in both hands, screen up, with its top edge toward the TV, and aim with it. A is big under your right thumb and B under your left. Aim at the middle of the TV and tap **Center** to recenter the pointer whenever it drifts.

Both Wii Remotes are for Wii games in Dolphin (see below), and you can switch between them mid-game, for example between Wii Party's minigames. They need the Mac app from the same version: an older Mac app ignores the phone while it sends motion.

### Changing the controller layout

Tap **Edit Layout** at the top of the controller screen. Drag a control to move it, and pinch it to resize it. For a small button, tap it and use the slider, or pinch on an empty part of the screen. **Show/Hide** turns controls on and off, including L3, R3 and Home, which start off. The D-pad and A/B/X/Y move as one block each. **Done** saves the layout on the phone, **Cancel** throws the changes away, and **Reset** goes back to the standard layout. Each controller keeps its own layout; Show/Hide and Reset only change the one on screen.

### Checking an emulator without a phone

Turn on **Test controller** in the Mac menu. It joins as a player that circles its sticks and presses A, B, X and Y in turn. In the emulator's controller settings, the DSU device's inputs should move (for Ryujinx: with the keyboard toggle on and the test controller as Player 1, keys get pressed). If that works but the phone doesn't, the problem is between the phone and the Mac. Turn the test controller off before mapping buttons, or it presses buttons while the emulator waits for yours.

### Dolphin (Mario Kart Wii)

1. In the Mac menu, click **Set Up Dolphin**. It adds MobiPad to Dolphin as a DSU server, if it isn't there yet, and adds three profiles for each player: a GameCube controller, a Wii Remote with tilt, and a Classic Controller. It doesn't change your current controller settings. If the server has to be added while Dolphin is open, it asks you to quit Dolphin first, because Dolphin overwrites its settings when it quits.
2. In Dolphin, open **Controllers**, set Port 1 to **Standard Controller**, click **Configure**, pick **MobiPad Player 1** under Profile, and click **Load**. For more players, load MobiPad Player 2 on Port 2, and so on.
3. For a Wii controller instead, set **Wii Remote 1** to **Emulated Wii Remote**, click **Configure**, and load **MobiPad Wii Remote Player 1** (phone on either Wii Remote) or **MobiPad Classic Player 1** (phone on Classic Controller). Wii Remote 2 gets Player 2, and so on.

The GameCube profiles match buttons by name:

| Phone | GameCube | | Phone | GameCube |
|---|---|---|---|---|
| A, B, X, Y | A, B, X, Y | | Left stick | Control Stick |
| RB | Z | | Right stick | C-Stick |
| LT / RT | L / R | | D-pad | D-pad |
| Menu | Start | | | |

LB, View, Home, L3 and R3 aren't used. To change a button, remap it in Dolphin and save the profile under another name, because Set Up Dolphin overwrites the MobiPad profiles.

The **Wii Remote** profiles use the phone's Wii Remote buttons as they are (A, B, 1, 2, −, Home, + and the D-pad), and map the phone's motion to the Wii Remote's accelerometer and gyroscope (Motion Input). One profile serves both ways of holding the phone. When you hold it sideways, the phone turns its motion and D-pad itself, so leave Dolphin's **Sideways Wii Remote** option off. Sideways, the phone's left end is the remote's IR end, like a Wii Remote in a Wii Wheel, and shaking works for Mario Kart's tricks and wheelies.

The pointer is Dolphin's **Point** under Motion Input, which follows the phone's gyroscope (it's on by default). The phone's **Center** button recenters it. If the pointer crosses the screen too quickly or too slowly when you turn the phone, change **Total Yaw** under Point (default 25°; higher is slower).

The **Classic Controller** profiles match buttons by name: A, B, X, Y; LB/RB are L/R, LT/RT are ZL/ZR, View is −, Menu is +, and Home, both sticks and the D-pad map directly. No tilt.

**By hand**, for example for a Nunchuk: in Controllers → **Alternate Input Sources**, enable **DSU Client** and add a server: IP `127.0.0.1`, port `26760`. Configure the emulated controller, pick the DSU device, then map each input by clicking it and pressing the matching button on the phone. Dolphin uses PlayStation names: **Cross = A, Circle = B, Square = X, Triangle = Y, L1/R1 = LB/RB, L2/R2 = LT/RT**. DSU device 0 is Player 1, device 1 is Player 2, and so on.

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

Not covered:
- The phone doesn't check that it's talking to the real Mac. A fake Mac on your network could see your button presses, but it can't control anything.
- The approval prompt shows whatever name the phone sends, and any device on your network can ask. Only click Allow when you're expecting a phone.
- The phone keeps its key in the app's settings, which are included in backups of the phone. Someone with a backup could act as that phone.

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
- tilt from the phone reaching that client as DSU motion

With only the Command Line Tools installed (no Xcode), point `swift test` at Swift Testing:

```sh
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $FW -Xlinker -F -Xlinker $FW \
  -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

## Status

Tried on real hardware:
- Both apps build and run from Xcode; the Mac app lives in the menu bar.
- An iPhone 16 Pro (and the iPhone Simulator) finds the Mac, gets approved, connects and plays.
- Dolphin reads both sticks and all buttons over DSU, as a GameCube controller.
- Set Up Dolphin's Wii Remote profile loads in Dolphin, and the pointer follows the phone left and right.
- Layout editing and dark mode draw correctly in the Simulator.

Covered by the package tests (`swift test`):
- **Connecting (FR-01, FR-02, CR-01, CR-02):** Bonjour discovery, connecting and disconnecting.
- **Pairing and encryption (CR-03, NFR-06).**
- **Streaming input (FR-06, NFR-01):** full snapshots on every change, resent every 50 ms, and old packets dropped.
- **Up to four players (FR-10)**, each keeping their player number across dropouts.
- **Automatic reconnect (FR-09)** and **latency (DR-03)**.
- **DSU for Dolphin and Cemu**, and **keyboard key mapping for Ryujinx**.
- **Test controller in the Mac menu.**
- **Set Up Dolphin (UX-01):** the DSU server entry and the GameCube, Wii Remote and Classic Controller profiles, with their key and input names checked against Dolphin's source.
- **Motion (both Wii Remotes):** the motion in the wire format, turning Core Motion readings into the controller's axes, the sideways turn (checked against Dolphin's own Sideways option), and the DSU motion fields as Dolphin reads them.

Not tried yet: Cemu, Ryujinx with keyboard output, four players at once, haptics, moving and resizing controls by touch, latency figures on a real network, and steering in Mario Kart Wii.

Work in progress: the pointer's up and down still needs fixing; see [TILT_NOTES.md](TILT_NOTES.md).

## License

MIT; see [LICENSE](LICENSE).

MobiPad isn't affiliated with or endorsed by Nintendo, Sony, Microsoft, Apple, or the Dolphin, Cemu or Ryujinx projects. Wii, GameCube and Mario Kart are trademarks of Nintendo, PlayStation of Sony, and Xbox of Microsoft. They're named here only to describe what MobiPad works with.
