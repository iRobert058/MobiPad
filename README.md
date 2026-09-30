# MobiPad

Use an iPhone as a wireless game controller for emulators on a Mac. Up to four phones can play at once. See [requirements.md](requirements.md).

```
iPhone ──Wi-Fi (UDP, Bonjour)──▶ Mac companion app ──DSU on localhost──▶ Dolphin
```

MobiPad doesn't create a system-wide virtual gamepad, because that needs a paid Apple entitlement. Emulators read it as a DSU controller instead. [docs/research/virtual-hid-macos.md](docs/research/virtual-hid-macos.md) explains why.

## Layout

```
MobiPadKit/            Swift package with all the logic, testable without Xcode
  MobiPadProtocol      controller state and the phone ↔ Mac message format
  MobiPadNetwork       phone side (ControllerLink, MacBrowser) and Mac side (ControllerHost)
  MobiPadDSU           DSU server that emulators connect to
iOS/                   iPhone app: find a Mac, then the controller
macOS/                 Mac menu bar app: player slots, latency, live input
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
4. Connect your iPhone by cable, turn on Developer Mode on it (Settings → Privacy & Security), and run the **MobiPad** scheme on it. Apps from a free account stop working after 7 days; running them again from Xcode renews them.
5. In the iPhone app, pick your Mac. The Mac's menu shows the phone as Player 1.

### Setting up Dolphin (once)

1. Controllers → **Alternate Input Sources** → enable **DSU Client** and add a server: IP `127.0.0.1`, port `26760`.
2. Configure the emulated controller (for Mario Kart Wii, a GameCube controller or a Classic Controller works well). Pick the DSU device, then map each input by clicking it and pressing the matching button on the phone.
   Dolphin uses PlayStation names: **Cross = A, Circle = B, Square = X, Triangle = Y, L1/R1 = LB/RB, L2/R2 = LT/RT**.
3. For more players, repeat step 2 for port 2, 3 or 4 and pick DSU device 1, 2 or 3.

## Tests

```sh
cd MobiPadKit && swift test
```

The tests include real UDP round-trips on localhost: phones joining, a fifth phone being turned away, reconnecting, latency, and a button press travelling all the way to a Dolphin-style DSU client.

With only the Command Line Tools installed (no Xcode), point `swift test` at Swift Testing:

```sh
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $FW -Xlinker -F -Xlinker $FW \
  -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

## Status

Done, and tested in the package:
- **Discovery and connecting (FR-01, CR-01, CR-02):** Bonjour, local network only.
- **Disconnecting (FR-02).**
- **Streaming input (FR-06, NFR-01):** full snapshots on every change, resent every 50 ms, and out-of-order packets dropped.
- **Player slots (FR-10):** up to four phones, and a returning phone gets its old player number back.
- **Automatic reconnect (FR-09):** the phone reconnects when the Mac goes quiet for 3 seconds, and the Mac frees a slot after 3 seconds of silence.
- **Latency (DR-03):** shown per player in the menu bar.
- **Test screen (FR-08):** live sticks and buttons per player in the menu bar.
- **DSU server for Dolphin:** four slots, localhost only.

Written, but not yet run on a device (the apps haven't been built yet):
- iPhone layout (FR-03, UX-02), with LB/RB/LT/RT added because Mario Kart needs them
- multi-touch (FR-04) and haptics (FR-05)
- keeping the screen awake while playing

Not started:
- pairing and encryption (CR-03, NFR-06)
- tilt steering
- keyboard output for emulators without DSU
