import Foundation
import Testing
@testable import MobiPadDSU

struct EdenSetupTests {
    /// A fresh Eden settings folder in the temporary directory.
    private let config: URL

    init() throws {
        config = FileManager.default.temporaryDirectory.appending(path: "EdenSetupTests-\(UUID())/eden")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: config.appending(path: path), encoding: .utf8)
    }

    private func write(_ text: String, to path: String) throws {
        try text.write(to: config.appending(path: path), atomically: true, encoding: .utf8)
    }

    /// The Controls lines of a freshly installed Eden 0.2.1, where every setting is at its default.
    static let freshSettings = """
        [Controls]
        motion_enabled\\default=true
        motion_enabled=true
        udp_input_servers\\default=true
        udp_input_servers=127.0.0.1:26760
        enable_udp_controller\\default=true
        enable_udp_controller=false

        [Core]
        use_multi_core\\default=true
        use_multi_core=true

        """

    /// Every profile MobiPad writes, in order: Pro Controller, then Joy-Con.
    static let profileNames = (1...4).map { "MobiPad Player \($0)" } + (1...4).map { "MobiPad Joy-Con Player \($0)" }

    @Test func turnsOnTheUDPControllerAndAddsAProfilePerPlayer() throws {
        try write(Self.freshSettings, to: "qt-config.ini")

        let outcome = try EdenSetup.install(configDirectory: config) { false }

        #expect(outcome == .installed(profileNames: Self.profileNames))
        // Eden's default server list already is MobiPad's server, so only the controller is turned on.
        #expect(try read("qt-config.ini") == Self.freshSettings.replacingOccurrences(
            of: "enable_udp_controller\\default=true\nenable_udp_controller=false",
            with: "enable_udp_controller\\default=false\nenable_udp_controller=true"
        ))
        for slot in 0..<4 {
            let profile = try read("input/MobiPad Player \(slot + 1).ini")
            #expect(profile.contains("button_a=\"engine:cemuhookudp,guid:\(EdenSetup.hostGUID),port:26760,pad:\(slot),button:8192\"\n"))
            let joyCon = try read("input/MobiPad Joy-Con Player \(slot + 1).ini")
            #expect(joyCon.contains("button_a=\"engine:cemuhookudp,guid:\(EdenSetup.hostGUID),port:26760,pad:\(slot),button:16384\"\n"))
        }
    }

    /// The server's place in the list decides its controllers' numbers.
    @Test func addsTheServerAfterTheUsersOwn() throws {
        try write("[Controls]\nudp_input_servers\\default=false\nudp_input_servers=192.168.1.20:26760\n", to: "qt-config.ini")

        _ = try EdenSetup.install(configDirectory: config) { false }

        let settings = INIText(try read("qt-config.ini"))
        #expect(settings.value(of: "udp_input_servers", in: "Controls") == "192.168.1.20:26760,127.0.0.1:26760")
        #expect(settings.value(of: "enable_udp_controller\\default", in: "Controls") == "false")
        #expect(settings.value(of: "enable_udp_controller", in: "Controls") == "true")
        #expect(try read("input/MobiPad Player 1.ini").contains(",pad:4,"))
        #expect(try read("input/MobiPad Player 4.ini").contains(",pad:7,"))
        #expect(try read("input/MobiPad Joy-Con Player 4.ini").contains(",pad:7,"))
    }

    /// Nothing to change, so Eden can stay open: profiles are read when its settings open.
    @Test func usesAServerTheUserAlreadyListed() throws {
        let settings = """
            [Controls]
            udp_input_servers\\default=false
            udp_input_servers=10.0.0.2:26760,127.0.0.1:26760
            enable_udp_controller\\default=false
            enable_udp_controller=true

            """
        try write(settings, to: "qt-config.ini")

        #expect(try EdenSetup.install(configDirectory: config) { true } == .installed(profileNames: Self.profileNames))
        #expect(try read("qt-config.ini") == settings)
        #expect(try read("input/MobiPad Player 2.ini").contains(",pad:5,"))
    }

    @Test func changesNothingWhileEdenIsOpen() throws {
        try write(Self.freshSettings, to: "qt-config.ini")

        #expect(try EdenSetup.install(configDirectory: config) { true } == .edenIsRunning)
        #expect(try read("qt-config.ini") == Self.freshSettings)
        #expect(!FileManager.default.fileExists(atPath: config.appending(path: "input").path(percentEncoded: false)))
    }

    @Test func needsEdenToHaveBeenOpenedOnce() throws {
        #expect(try EdenSetup.install(configDirectory: config) { false } == .edenNotFound)
    }

    /// Eden's key names (settings_input.cpp), so a typo can't leave a button unmapped.
    static let edenKeys: Set<String> = [
        "button_a", "button_b", "button_x", "button_y", "button_lstick", "button_rstick", "button_l", "button_r",
        "button_zl", "button_zr", "button_plus", "button_minus", "button_dleft", "button_dup", "button_dright",
        "button_ddown", "button_slleft", "button_srleft", "button_home", "button_screenshot", "button_slright",
        "button_srright", "lstick", "rstick", "motionleft", "motionright",
    ]

    @Test func profileMapsEveryInputEdenHas() {
        let ini = INIText(EdenSetup.proControllerProfile(pad: 0, port: 26760))
        for key in Self.edenKeys {
            // Without a false default flag, Eden ignores the value.
            #expect(ini.value(of: "\(key)\\default", in: "Controls") == "false", "\(key)")
            #expect(ini.value(of: key, in: "Controls")?.hasPrefix("\"engine:cemuhookudp,") == true, "\(key)")
        }
        #expect(EdenSetup.proControllerProfile(pad: 0, port: 26760).split(separator: "\n").count == 1 + 2 * Self.edenKeys.count)
    }

    /// The same mapping Eden makes itself, so the phone's sticks and buttons land where Eden expects.
    @Test func profileMatchesEdensAutomaticMapping() {
        let ini = INIText(EdenSetup.proControllerProfile(pad: 2, port: 26760))
        func parameters(_ key: String) -> String? { ini.value(of: key, in: "Controls") }
        let device = "engine:cemuhookudp,guid:0000000000000000000000007f000001,port:26760,pad:2"
        #expect(parameters("button_a") == "\"\(device),button:8192\"") // Circle: the phone's B, on the right
        #expect(parameters("button_b") == "\"\(device),button:16384\"") // Cross: the phone's A, at the bottom
        #expect(parameters("button_zr") == "\"\(device),button:512\"") // R2
        #expect(parameters("button_home") == "\"\(device),button:262144\"")
        #expect(parameters("lstick") == "\"\(device),axis_x:0,axis_y:1\"")
        #expect(parameters("rstick") == "\"\(device),axis_x:2,axis_y:3\"")
        #expect(parameters("motionleft") == "\"\(device),motion:0\"")
    }

    /// The keys of a right Joy-Con (Eden's EmulatedController reads these for one), plus its controller type.
    @Test func joyConProfileIsARightJoyConWithEveryButtonItHas() {
        let profile = EdenSetup.joyConProfile(pad: 1, port: 26760)
        let ini = INIText(profile)
        func parameters(_ key: String) -> String? { ini.value(of: key, in: "Controls") }
        let device = "engine:cemuhookudp,guid:0000000000000000000000007f000001,port:26760,pad:1"

        #expect(ini.value(of: "type\\default", in: "Controls") == "false")
        #expect(ini.value(of: "type", in: "Controls") == "3")
        let keys = profile.split(separator: "\n").dropFirst().compactMap { line -> String? in
            let key = String(line.split(separator: "=")[0])
            return key.hasSuffix("\\default") || key == "type" ? nil : key
        }
        #expect(Set(keys).isSubset(of: Self.edenKeys))
        #expect(Set(keys).isSuperset(of: [
            "button_a", "button_b", "button_x", "button_y", "button_r", "button_zr", "button_slright",
            "button_srright", "button_plus", "button_home", "button_rstick", "rstick", "motionright",
        ]))
        for key in keys {
            #expect(ini.value(of: "\(key)\\default", in: "Controls") == "false", "\(key)")
        }
        // The phone's Joy-Con layouts send the Joy-Con's own letters as the phone's A, B, X and Y.
        #expect(parameters("button_a") == "\"\(device),button:16384\"") // Cross
        #expect(parameters("button_b") == "\"\(device),button:8192\"") // Circle
        #expect(parameters("button_x") == "\"\(device),button:32768\"") // Square
        #expect(parameters("button_y") == "\"\(device),button:4096\"") // Triangle
        #expect(parameters("button_slright") == "\"\(device),button:1024\"") // L1: the phone's LB
        #expect(parameters("button_srright") == "\"\(device),button:256\"") // L2: the phone's LT
        #expect(parameters("rstick") == "\"\(device),axis_x:2,axis_y:3\"")
    }

    /// Eden formats 127.0.0.1 as "00000000-0000-0000-0000-0000" + "%06x" of 0x7f000001, without dashes.
    @Test func guidFollowsEdensFormula() {
        let formatted = "00000000-0000-0000-0000-0000" + String(format: "%06x", 0x7F00_0001)
        #expect(EdenSetup.hostGUID == formatted.replacingOccurrences(of: "-", with: ""))
    }
}
