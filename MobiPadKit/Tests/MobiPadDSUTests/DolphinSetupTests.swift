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

    @Test func addsTheServerAndAProfilePerPlayer() throws {
        let outcome = try DolphinSetup.install(configDirectory: config) { false }

        let names = ["MobiPad Player 1", "MobiPad Player 2", "MobiPad Player 3", "MobiPad Player 4"]
        #expect(outcome == .installed(profileNames: names))
        #expect(try read("DSUClient.ini") == "[Server]\nEntries = MobiPad:127.0.0.1:26760;\nEnabled = True\n")
        for (slot, name) in names.enumerated() {
            #expect(try read("Profiles/GCPad/\(name).ini").contains("Device = DSUClient/\(slot)/MobiPad\n"))
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

        #expect(outcome == .installed(profileNames: (1...4).map { "MobiPad Player \($0)" }))
        #expect(try read("DSUClient.ini") == settings)
        #expect(try read("Profiles/GCPad/MobiPad Player 2.ini").contains("Device = DSUClient/1/Phone\n"))
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
