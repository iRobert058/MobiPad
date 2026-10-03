import Foundation
import Testing
@testable import MobiPadDSU

struct DolphinSetupTests {
    /// A fresh Dolphin settings folder in the temporary directory.
    private let config: URL

    init() throws {
        config = FileManager.default.temporaryDirectory.appending(path: "DolphinSetupTests-\(UUID())/Config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: config.appending(path: path), encoding: .utf8)
    }

    private func write(_ text: String, to path: String) throws {
        try text.write(to: config.appending(path: path), atomically: true, encoding: .utf8)
    }

    /// Every profile MobiPad writes, in order: GameCube, then Wii Remote, then Classic Controller.
    static let allProfileNames = (1...4).map { "MobiPad Player \($0)" }
        + (1...4).map { "MobiPad Wii Remote Player \($0)" }
        + (1...4).map { "MobiPad Classic Player \($0)" }

    @Test func addsTheServerAndAProfilePerPlayer() throws {
        let outcome = try DolphinSetup.install(configDirectory: config) { false }

        #expect(outcome == .installed(profileNames: Self.allProfileNames))
        #expect(try read("DSUClient.ini") == "[Server]\nEntries = MobiPad:127.0.0.1:26760;\nEnabled = True\n")
        for slot in 0..<4 {
            let device = "Device = DSUClient/\(slot)/MobiPad\n"
            #expect(try read("Profiles/GCPad/MobiPad Player \(slot + 1).ini").contains(device))
            #expect(try read("Profiles/Wiimote/MobiPad Wii Remote Player \(slot + 1).ini").contains(device))
            #expect(try read("Profiles/Wiimote/MobiPad Classic Player \(slot + 1).ini").contains(device))
        }
    }

    @Test func keepsOtherServersAndSettings() throws {
        try write("[Server]\nEnabled = False\nEntries = Deck:192.168.1.20:26760;\n\n[Other]\nKey = Value\n", to: "DSUClient.ini")

        _ = try DolphinSetup.install(configDirectory: config) { false }

        #expect(try read("DSUClient.ini") == """
            [Server]
            Enabled = True
            Entries = Deck:192.168.1.20:26760;MobiPad:127.0.0.1:26760;

            [Other]
            Key = Value

            """)
    }

    /// The server is already there, so Dolphin can stay open: profiles are read when the dialog opens.
    @Test func usesTheNameOfAServerTheUserAlreadyAdded() throws {
        let settings = "[Server]\nEnabled = True\nEntries = Phone:localhost:26760;\n"
        try write(settings, to: "DSUClient.ini")

        let outcome = try DolphinSetup.install(configDirectory: config) { true }

        #expect(outcome == .installed(profileNames: Self.allProfileNames))
        #expect(try read("DSUClient.ini") == settings)
        #expect(try read("Profiles/GCPad/MobiPad Player 2.ini").contains("Device = DSUClient/1/Phone\n"))
        #expect(try read("Profiles/Wiimote/MobiPad Wii Remote Player 2.ini").contains("Device = DSUClient/1/Phone\n"))
    }

    @Test func changesNothingWhileDolphinIsOpen() throws {
        let settings = "[Server]\nEnabled = False\nEntries = MobiPad:127.0.0.1:26760;\n"
        try write(settings, to: "DSUClient.ini")

        #expect(try DolphinSetup.install(configDirectory: config) { true } == .dolphinIsRunning)
        #expect(try read("DSUClient.ini") == settings)
        #expect(!FileManager.default.fileExists(atPath: config.appending(path: "Profiles").path(percentEncoded: false)))
    }

    @Test func needsDolphinToHaveBeenOpenedOnce() throws {
        let missing = config.appending(path: "Missing")
        #expect(try DolphinSetup.install(configDirectory: missing) { false } == .dolphinNotFound)
    }

    /// Checked against the inputs Dolphin's DSU client creates (DualShockUDPClient.cpp), so a typo
    /// can't leave a button unmapped.
    @Test func profileUsesOnlyInputsDolphinKnows() {
        let dolphinInputs: Set<String> = [
            "Pad W", "Pad S", "Pad E", "Pad N", "Square", "Cross", "Circle", "Triangle", "L1", "R1", "L2", "R2",
            "L3", "R3", "Share", "Options", "PS", "Touch Button",
            "Left X-", "Left X+", "Left Y-", "Left Y+", "Right X-", "Right X+", "Right Y-", "Right Y+",
        ]
        let profile = DolphinSetup.gameCubeProfile(slot: 0, serverName: "MobiPad")
        // Input names sit between backticks.
        let used = profile.split(separator: "`", omittingEmptySubsequences: false).enumerated()
            .filter { !$0.offset.isMultiple(of: 2) }
            .map { String($0.element) }

        #expect(used.count == 22)
        #expect(Set(used).isSubset(of: dolphinInputs))
        #expect(profile.contains("Buttons/A = `Cross`\n"))
        #expect(profile.contains("Main Stick/Calibration = 100.00\n"))
    }

    /// The inputs Dolphin's DSU client creates (DualShockUDPClient.cpp), motion included.
    static let dsuInputs: Set<String> = [
        "Pad W", "Pad S", "Pad E", "Pad N", "Square", "Cross", "Circle", "Triangle", "L1", "R1", "L2", "R2",
        "L3", "R3", "Share", "Options", "PS", "Touch Button",
        "Left X-", "Left X+", "Left Y-", "Left Y+", "Right X-", "Right X+", "Right Y-", "Right Y+",
        "Accel Up", "Accel Down", "Accel Left", "Accel Right", "Accel Forward", "Accel Backward",
        "Gyro Pitch Up", "Gyro Pitch Down", "Gyro Roll Left", "Gyro Roll Right", "Gyro Yaw Left", "Gyro Yaw Right",
    ]

    /// Profile keys of an emulated Wii Remote, from Dolphin's WiimoteEmu.h/.cpp (the pointer group is
    /// "IMUIR"), IMUAccelerometer.cpp, IMUGyroscope.cpp, IMUCursor.cpp and Extension/Classic.h. A
    /// misspelled key would be silently ignored.
    static let wiimoteKeys: Set<String> = {
        var keys: Set<String> = ["Device", "Extension", "Options/Sideways Wiimote", "Options/Upright Wiimote", "IMUIR/Recenter"]
        for button in ["A", "B", "1", "2", "-", "+", "Home"] { keys.insert("Buttons/\(button)") }
        for direction in ["Up", "Down", "Left", "Right"] {
            keys.insert("D-Pad/\(direction)")
            keys.insert("Classic/D-Pad/\(direction)")
            keys.insert("Classic/Left Stick/\(direction)")
            keys.insert("Classic/Right Stick/\(direction)")
        }
        for direction in ["Up", "Down", "Left", "Right", "Forward", "Backward"] { keys.insert("IMUAccelerometer/\(direction)") }
        for direction in ["Pitch Up", "Pitch Down", "Roll Left", "Roll Right", "Yaw Left", "Yaw Right"] {
            keys.insert("IMUGyroscope/\(direction)")
        }
        for button in ["A", "B", "X", "Y", "ZL", "ZR", "-", "+", "Home"] { keys.insert("Classic/Buttons/\(button)") }
        for trigger in ["L", "R", "L-Analog", "R-Analog"] { keys.insert("Classic/Triggers/\(trigger)") }
        keys.formUnion(["Classic/Left Stick/Calibration", "Classic/Right Stick/Calibration"])
        return keys
    }()

    /// The `Key = Value` lines of a profile.
    static func settings(_ profile: String) -> [String: String] {
        var settings: [String: String] = [:]
        for line in profile.split(separator: "\n") where line.contains(" = ") {
            let parts = line.split(separator: " = ", maxSplits: 1)
            settings[String(parts[0])] = String(parts[1])
        }
        return settings
    }

    /// The input a mapping names, without its backticks.
    static func input(_ value: String) -> String? {
        value.hasPrefix("`") && value.hasSuffix("`") ? String(value.dropFirst().dropLast()) : nil
    }

    @Test func wiiRemoteProfileUsesOnlyNamesDolphinKnows() {
        let settings = Self.settings(DolphinSetup.wiiRemoteProfile(slot: 0, serverName: "MobiPad"))

        #expect(Set(settings.keys).isSubset(of: Self.wiimoteKeys))
        #expect(Set(settings.values.compactMap(Self.input)).isSubset(of: Self.dsuInputs))
        #expect(settings.values.compactMap(Self.input).count == 24)
        // The phone's Center button recenters Dolphin's pointer.
        #expect(settings["IMUIR/Recenter"] == "`R3`")
        // The phone turns its motion sideways itself, so Dolphin mustn't turn it again.
        #expect(settings["Options/Sideways Wiimote"] == "False")
        #expect(settings["Extension"] == "None")
    }

    /// Like Dolphin's own defaults: each Wii Remote motion direction reads the DSU input of the same name.
    @Test func wiiRemoteMotionMapsOneToOne() {
        let settings = Self.settings(DolphinSetup.wiiRemoteProfile(slot: 0, serverName: "MobiPad"))
        for direction in ["Up", "Down", "Left", "Right", "Forward", "Backward"] {
            #expect(settings["IMUAccelerometer/\(direction)"] == "`Accel \(direction)`")
        }
        for direction in ["Pitch Up", "Pitch Down", "Roll Left", "Roll Right", "Yaw Left", "Yaw Right"] {
            #expect(settings["IMUGyroscope/\(direction)"] == "`Gyro \(direction)`")
        }
    }

    @Test func classicProfileUsesOnlyNamesDolphinKnows() {
        let settings = Self.settings(DolphinSetup.classicControllerProfile(slot: 0, serverName: "MobiPad"))

        #expect(Set(settings.keys).isSubset(of: Self.wiimoteKeys))
        #expect(Set(settings.values.compactMap(Self.input)).isSubset(of: Self.dsuInputs))
        #expect(settings.values.compactMap(Self.input).count == 25)
        #expect(settings["Extension"] == "Classic")
        // No motion: the Classic Controller layout doesn't tilt.
        #expect(!settings.keys.contains { $0.hasPrefix("IMU") })
    }

    @Test func iniEditsKeepLayoutAndIgnoreKeyCase() {
        var ini = INIText("; comment\n[A]\nenabled = False\n\n[B]\nX = 1")
        ini.set("Enabled", to: "True", in: "A")
        ini.set("New", to: "2", in: "A")
        ini.set("Y", to: "3", in: "C")

        #expect(ini.value(of: "ENABLED", in: "A") == "True")
        #expect(ini.value(of: "X", in: "A") == nil)
        #expect(ini.text == "; comment\n[A]\nEnabled = True\nNew = 2\n\n[B]\nX = 1\n[C]\nY = 3\n")
    }
}
