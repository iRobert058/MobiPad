import Foundation

/// Sets Dolphin up for MobiPad, so players don't have to map every button by hand (UX-01).
///
/// Makes sure Dolphin's DSU client knows the MobiPad server, and writes a GameCube controller
/// profile per player ("MobiPad Player 1" to 4) that players load in Dolphin's controller settings.
/// It never changes a port's current mapping.
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

        let profileDirectory = configDirectory.appending(path: "Profiles/GCPad", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        var profileNames: [String] = []
        for slot in 0..<DSU.slotCount {
            let name = "MobiPad Player \(slot + 1)"
            try gameCubeProfile(slot: slot, serverName: serverName)
                .write(to: profileDirectory.appending(path: "\(name).ini"), atomically: true, encoding: .utf8)
            profileNames.append(name)
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
