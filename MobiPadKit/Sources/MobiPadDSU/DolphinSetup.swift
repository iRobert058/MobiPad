import Foundation

/// Sets Dolphin up for MobiPad, so players don't have to map every button by hand (UX-01).
///
/// Makes sure Dolphin's DSU client knows the MobiPad server, and writes profiles per player that
/// players load in Dolphin's controller settings: a GameCube controller ("MobiPad Player 1" to 4), and
/// for Wii games a Wii Remote with tilt ("MobiPad Wii Remote Player 1" to 4) and a Classic Controller
/// ("MobiPad Classic Player 1" to 4). It never changes a port's current mapping.
///
/// Every profile sends the game's rumble to the DSU controller's `Motor` output, which the phone plays.
/// Stock Dolphin's DSU client has no outputs, so there the mapping does nothing until Dolphin learns
/// DSU rumble (see the README).
public enum DolphinSetup {
    public enum Outcome: Equatable, Sendable {
        case installed(profileNames: [String])
        /// The server list has to change, and Dolphin overwrites its settings when it quits.
        case dolphinIsRunning
        /// There's no settings folder until Dolphin has been opened once.
        case dolphinNotFound
    }

    /// Where Dolphin keeps its settings on macOS.
    public static let defaultConfigDirectory = URL.homeDirectory
        .appending(path: "Library/Application Support/Dolphin/Config", directoryHint: .isDirectory)

    static let serverName = "MobiPad"

    /// - Parameter isDolphinRunning: asked only when the server list has to change.
    public static func install(
        configDirectory: URL = defaultConfigDirectory,
        port: UInt16 = DSU.defaultPort,
        isDolphinRunning: () -> Bool
    ) throws -> Outcome {
        guard FileManager.default.fileExists(atPath: configDirectory.path(percentEncoded: false)) else {
            return .dolphinNotFound
        }

        let clientFile = configDirectory.appending(path: "DSUClient.ini")
        let oldSettings = (try? String(contentsOf: clientFile, encoding: .utf8)) ?? ""
        let (newSettings, serverName) = enablingServer(port: port, in: oldSettings)
        if newSettings != oldSettings {
            guard !isDolphinRunning() else { return .dolphinIsRunning }
            try newSettings.write(to: clientFile, atomically: true, encoding: .utf8)
        }

        var profileNames: [String] = []
        for kind in ProfileKind.allCases {
            let profileDirectory = configDirectory.appending(path: "Profiles/\(kind.folder)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
            for slot in 0..<DSU.slotCount {
                let name = kind.profileName(slot: slot)
                try kind.profile(slot: slot, serverName: serverName)
                    .write(to: profileDirectory.appending(path: "\(name).ini"), atomically: true, encoding: .utf8)
                profileNames.append(name)
            }
        }
        return .installed(profileNames: profileNames)
    }

    /// Turns on Dolphin's DSU client and adds the MobiPad server, unless a server on this Mac's port is
    /// already listed. Returns the new settings and the name Dolphin knows the server by.
    static func enablingServer(port: UInt16, in settings: String) -> (settings: String, serverName: String) {
        var ini = INIText(settings)
        var entries = ini.value(of: "Entries", in: "Server") ?? ""

        // Each entry is "name:address:port;".
        let existing = entries.split(separator: ";").map { $0.split(separator: ":", omittingEmptySubsequences: false) }
            .first { $0.count == 3 && ["127.0.0.1", "localhost"].contains($0[1]) && $0[2] == "\(port)" }
        let serverName = existing.map { String($0[0]) } ?? Self.serverName
        if existing == nil {
            if !entries.isEmpty, !entries.hasSuffix(";") { entries += ";" }
            ini.set("Entries", to: entries + "\(serverName):127.0.0.1:\(port);", in: "Server")
        }
        if ini.value(of: "Enabled", in: "Server")?.lowercased() != "true" {
            ini.set("Enabled", to: "True", in: "Server")
        }
        return (ini.text, serverName)
    }

    enum ProfileKind: CaseIterable {
        case gameCube, wiiRemote, classicController

        /// Dolphin's profile folder for the emulated controller.
        var folder: String {
            switch self {
            case .gameCube: "GCPad"
            case .wiiRemote, .classicController: "Wiimote"
            }
        }

        func profileName(slot: Int) -> String {
            switch self {
            case .gameCube: "MobiPad Player \(slot + 1)"
            case .wiiRemote: "MobiPad Wii Remote Player \(slot + 1)"
            case .classicController: "MobiPad Classic Player \(slot + 1)"
            }
        }

        func profile(slot: Int, serverName: String) -> String {
            switch self {
            case .gameCube: gameCubeProfile(slot: slot, serverName: serverName)
            case .wiiRemote: wiiRemoteProfile(slot: slot, serverName: serverName)
            case .classicController: classicControllerProfile(slot: slot, serverName: serverName)
            }
        }
    }

    /// A Wii Remote, for the phone's Wii Remote layouts, with the phone's motion sensors as its
    /// accelerometer and gyroscope.
    ///
    /// The IMU groups map one to one, as in Dolphin's own defaults. "Sideways Wiimote" stays off: when
    /// the player holds the phone sideways, the phone turns its motion and D-pad itself, so this one
    /// profile works for both ways of holding it. The phone sends its Wii Remote buttons as
    /// A → Cross, B → Circle, 1 → Square, 2 → Triangle, − → Share, + → Options and Home → PS.
    ///
    /// The pointer comes from Dolphin's "Point" under Motion Input (`IMUIR`), which follows the
    /// gyroscope and is on by default. The phone's Center button (R3) recenters it on where the
    /// phone points.
    ///
    /// The pointer's Accelerometer Influence is off, so up and down follow the gyroscope alone, like
    /// left and right. With it on, Dolphin took the phone's own movement (a quick aim, or a thumb
    /// pushing a button) for a change of tilt and jumped the pointer up or down by a few degrees.
    ///
    /// Dolphin's gyroscope calibration is off. iOS already removes the gyroscope's offset, and
    /// Dolphin's calibration starts from the first reading after the phone connects: taken while the
    /// phone moves, that makes the pointer drift until the phone is held perfectly still for 3 seconds.
    static func wiiRemoteProfile(slot: Int, serverName: String) -> String {
        """
        [Profile]
        Device = DSUClient/\(slot)/\(serverName)
        Buttons/A = `Cross`
        Buttons/B = `Circle`
        Buttons/1 = `Square`
        Buttons/2 = `Triangle`
        Buttons/- = `Share`
        Buttons/+ = `Options`
        Buttons/Home = `PS`
        D-Pad/Up = `Pad N`
        D-Pad/Down = `Pad S`
        D-Pad/Left = `Pad W`
        D-Pad/Right = `Pad E`
        IMUAccelerometer/Up = `Accel Up`
        IMUAccelerometer/Down = `Accel Down`
        IMUAccelerometer/Left = `Accel Left`
        IMUAccelerometer/Right = `Accel Right`
        IMUAccelerometer/Forward = `Accel Forward`
        IMUAccelerometer/Backward = `Accel Backward`
        IMUGyroscope/Pitch Up = `Gyro Pitch Up`
        IMUGyroscope/Pitch Down = `Gyro Pitch Down`
        IMUGyroscope/Roll Left = `Gyro Roll Left`
        IMUGyroscope/Roll Right = `Gyro Roll Right`
        IMUGyroscope/Yaw Left = `Gyro Yaw Left`
        IMUGyroscope/Yaw Right = `Gyro Yaw Right`
        IMUGyroscope/Calibration Period = 0
        IMUIR/Recenter = `R3`
        IMUIR/Accelerometer Influence = 0
        Options/Sideways Wiimote = False
        Extension = None
        Rumble/Motor = `Motor`

        """
    }

    /// A Wii Remote with a Classic Controller attached, for the phone's Classic Controller layout, matched
    /// by button name like the GameCube profile. LB and RB are the shoulder buttons L and R, LT and RT
    /// are ZL and ZR, View is − and Menu is +. The sticks get the same full-circle calibration.
    static func classicControllerProfile(slot: Int, serverName: String) -> String {
        """
        [Profile]
        Device = DSUClient/\(slot)/\(serverName)
        Extension = Classic
        Classic/Buttons/A = `Cross`
        Classic/Buttons/B = `Circle`
        Classic/Buttons/X = `Square`
        Classic/Buttons/Y = `Triangle`
        Classic/Buttons/ZL = `L2`
        Classic/Buttons/ZR = `R2`
        Classic/Buttons/- = `Share`
        Classic/Buttons/+ = `Options`
        Classic/Buttons/Home = `PS`
        Classic/Left Stick/Up = `Left Y+`
        Classic/Left Stick/Down = `Left Y-`
        Classic/Left Stick/Left = `Left X-`
        Classic/Left Stick/Right = `Left X+`
        Classic/Left Stick/Calibration = 100.00
        Classic/Right Stick/Up = `Right Y+`
        Classic/Right Stick/Down = `Right Y-`
        Classic/Right Stick/Left = `Right X-`
        Classic/Right Stick/Right = `Right X+`
        Classic/Right Stick/Calibration = 100.00
        Classic/Triggers/L = `L1`
        Classic/Triggers/R = `R1`
        Classic/Triggers/L-Analog = `L1`
        Classic/Triggers/R-Analog = `R1`
        Classic/D-Pad/Up = `Pad N`
        Classic/D-Pad/Down = `Pad S`
        Classic/D-Pad/Left = `Pad W`
        Classic/D-Pad/Right = `Pad E`
        Rumble/Motor = `Motor`

        """
    }

    /// A standard GameCube controller, matched by button name: the phone's A is the GameCube's A.
    /// LB, View, Home, L3 and R3 have no GameCube counterpart.
    ///
    /// Input names are the ones Dolphin's DSU client gives the buttons (DualShockUDPClient.cpp), and
    /// MobiPad sends A as Cross, B as Circle, X as Square and Y as Triangle. A calibration of one 100%
    /// sample is a full circle, which is how far MobiPad's sticks reach; without it, Dolphin expects the
    /// GameCube's octagon. The phone's triggers are all or nothing, so each one presses its GameCube
    /// trigger fully, including the click at the end.
    static func gameCubeProfile(slot: Int, serverName: String) -> String {
        """
        [Profile]
        Device = DSUClient/\(slot)/\(serverName)
        Buttons/A = `Cross`
        Buttons/B = `Circle`
        Buttons/X = `Square`
        Buttons/Y = `Triangle`
        Buttons/Z = `R1`
        Buttons/Start = `Options`
        Main Stick/Up = `Left Y+`
        Main Stick/Down = `Left Y-`
        Main Stick/Left = `Left X-`
        Main Stick/Right = `Left X+`
        Main Stick/Calibration = 100.00
        C-Stick/Up = `Right Y+`
        C-Stick/Down = `Right Y-`
        C-Stick/Left = `Right X-`
        C-Stick/Right = `Right X+`
        C-Stick/Calibration = 100.00
        Triggers/L = `L2`
        Triggers/R = `R2`
        Triggers/L-Analog = `L2`
        Triggers/R-Analog = `R2`
        D-Pad/Up = `Pad N`
        D-Pad/Down = `Pad S`
        D-Pad/Left = `Pad W`
        D-Pad/Right = `Pad E`
        Rumble/Motor = `Motor`

        """
    }
}

/// Reads and changes `Key = Value` lines in Dolphin's INI files, leaving every other line as it was.
/// Keys are case-insensitive, as in Dolphin.
struct INIText {
    private var lines: [String]

    init(_ text: String) {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
    }

    var text: String { lines.map { $0 + "\n" }.joined() }

    func value(of key: String, in section: String) -> String? {
        index(of: key, in: section).map { value(at: $0) }
    }

    mutating func set(_ key: String, to value: String, in section: String) {
        let line = "\(key) = \(value)"
        if let index = index(of: key, in: section) {
            lines[index] = line
        } else if let range = range(of: section) {
            // After the section's last setting, before any blank lines that separate it from the next.
            let end = range.last { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty } ?? range.lowerBound - 1
            lines.insert(line, at: end + 1)
        } else {
            lines += ["[\(section)]", line]
        }
    }

    /// The lines inside a section, not counting its header.
    private func range(of section: String) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { Self.sectionName($0) == section }) else { return nil }
        let end = lines[(header + 1)...].firstIndex { Self.sectionName($0) != nil } ?? lines.endIndex
        return (header + 1)..<end
    }

    private func index(of key: String, in section: String) -> Int? {
        range(of: section)?.first { index in
            let parts = lines[index].split(separator: "=", maxSplits: 1)
            return parts.count == 2
                && parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame
        }
    }

    private func value(at index: Int) -> String {
        let parts = lines[index].split(separator: "=", maxSplits: 1)
        return parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private static func sectionName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }
}
