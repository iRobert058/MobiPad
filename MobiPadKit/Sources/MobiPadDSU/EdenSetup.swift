import Foundation

/// Sets Eden (a Switch emulator) up for MobiPad, so players don't have to map every button by hand (UX-01).
///
/// Turns on Eden's DSU client (its "UDP controller") and makes sure it lists the MobiPad server, then
/// writes profiles per player that players load in Eden's controller settings: a Pro Controller
/// ("MobiPad Player 1" to 4) and a single right Joy-Con ("MobiPad Joy-Con Player 1" to 4). It never
/// changes a player's current mapping.
///
/// Names and formats come from Eden's source: `qt-config.ini` and the profiles in `input/` keep each
/// value next to a `\default` flag, and Eden ignores the value unless that flag is `false`.
public enum EdenSetup {
    public enum Outcome: Equatable, Sendable {
        case installed(profileNames: [String])
        /// The settings have to change, and Eden overwrites its settings when it quits.
        case edenIsRunning
        /// There are no settings until Eden has been opened once.
        case edenNotFound
    }

    /// Where Eden keeps its settings on macOS.
    public static let defaultConfigDirectory = URL.homeDirectory
        .appending(path: ".config/eden", directoryHint: .isDirectory)

    /// Eden kept yuzu's bundle identifier.
    public static let bundleIdentifier = "com.yuzu-emu.yuzu"

    static let section = "Controls"
    static let host = "127.0.0.1"
    /// Eden's server list when the user never changed it.
    static let defaultServers = ["127.0.0.1:26760"]
    /// Eden names a server's controllers after the server's IPv4 address (`UDPClient::GetHostUUID`):
    /// 127.0.0.1 is 0x7f000001.
    static let hostGUID = "0000000000000000000000007f000001"
    /// Eden numbers controllers across servers: the first server's four are pads 0 to 3, the next 4 to 7.
    static let padsPerServer = 4

    /// - Parameter isEdenRunning: asked only when the settings have to change.
    public static func install(
        configDirectory: URL = defaultConfigDirectory,
        port: UInt16 = DSU.defaultPort,
        isEdenRunning: () -> Bool
    ) throws -> Outcome {
        let settingsFile = configDirectory.appending(path: "qt-config.ini")
        guard FileManager.default.fileExists(atPath: settingsFile.path(percentEncoded: false)) else {
            return .edenNotFound
        }

        let oldSettings = try String(contentsOf: settingsFile, encoding: .utf8)
        let (newSettings, serverIndex) = enablingServer(port: port, in: oldSettings)
        if newSettings != oldSettings {
            guard !isEdenRunning() else { return .edenIsRunning }
            try newSettings.write(to: settingsFile, atomically: true, encoding: .utf8)
        }

        let profileDirectory = configDirectory.appending(path: "input", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        var profileNames: [String] = []
        for kind in ProfileKind.allCases {
            for slot in 0..<DSU.slotCount {
                let name = kind.profileName(slot: slot)
                try kind.profile(pad: serverIndex * padsPerServer + slot, port: port)
                    .write(to: profileDirectory.appending(path: "\(name).ini"), atomically: true, encoding: .utf8)
                profileNames.append(name)
            }
        }
        return .installed(profileNames: profileNames)
    }

    enum ProfileKind: CaseIterable {
        /// For the phone's Classic Controller layout.
        case proController
        /// For the phone's Joy-Con layouts. One profile serves both: the game decides how a single
        /// Joy-Con is held.
        case joyCon

        func profileName(slot: Int) -> String {
            switch self {
            case .proController: "MobiPad Player \(slot + 1)"
            case .joyCon: "MobiPad Joy-Con Player \(slot + 1)"
            }
        }

        func profile(pad: Int, port: UInt16) -> String {
            switch self {
            case .proController: proControllerProfile(pad: pad, port: port)
            case .joyCon: joyConProfile(pad: pad, port: port)
            }
        }
    }

    /// Turns on Eden's UDP controller and adds the MobiPad server, unless it's already listed. Returns
    /// the new settings and the server's place in the list, which decides its controllers' numbers.
    static func enablingServer(port: UInt16, in settings: String) -> (settings: String, serverIndex: Int) {
        var ini = INIText(settings, separator: "=")
        let server = "\(host):\(port)"

        var servers = defaultServers
        if isSet("udp_input_servers", in: ini) {
            servers = (ini.value(of: "udp_input_servers", in: section) ?? "")
                .replacingOccurrences(of: "\"", with: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let serverIndex: Int
        if let index = servers.firstIndex(of: server) {
            serverIndex = index
        } else {
            servers.append(server)
            serverIndex = servers.count - 1
            ini.set("udp_input_servers\\default", to: "false", in: section)
            ini.set("udp_input_servers", to: servers.joined(separator: ","), in: section)
        }

        if !isSet("enable_udp_controller", in: ini) || ini.value(of: "enable_udp_controller", in: section) != "true" {
            ini.set("enable_udp_controller\\default", to: "false", in: section)
            ini.set("enable_udp_controller", to: "true", in: section)
        }
        return (ini.text, serverIndex)
    }

    /// Whether Eden uses the stored value rather than its default.
    private static func isSet(_ key: String, in ini: INIText) -> Bool {
        ini.value(of: "\(key)\\default", in: section)?.lowercased() == "false"
    }

    /// Eden's DSU button numbers (`PadButton` in udp_client.h).
    enum PadButton: Int {
        case share = 0x0001, l3 = 0x0002, r3 = 0x0004, options = 0x0008
        case up = 0x0010, right = 0x0020, down = 0x0040, left = 0x0080
        case l2 = 0x0100, r2 = 0x0200, l1 = 0x0400, r1 = 0x0800
        case triangle = 0x1000, circle = 0x2000, cross = 0x4000, square = 0x8000
        case home = 0x40000, touchHardPress = 0x80000
    }

    /// Eden's own automatic mapping for a DSU controller (`UDPClient::GetButtonMappingForDevice`). It
    /// goes by position, as on a Switch controller: the right face button is A and the bottom one is B.
    /// So the phone's B (right, sent as Circle) is the Switch's A, and its A (bottom, Cross) is B.
    static let buttons: [(key: String, button: PadButton)] = [
        ("button_a", .circle), ("button_b", .cross), ("button_x", .triangle), ("button_y", .square),
        ("button_lstick", .l3), ("button_rstick", .r3),
        ("button_l", .l1), ("button_r", .r1), ("button_zl", .l2), ("button_zr", .r2),
        ("button_plus", .options), ("button_minus", .share),
        ("button_dleft", .left), ("button_dup", .up), ("button_dright", .right), ("button_ddown", .down),
        ("button_slleft", .l2), ("button_srleft", .r2), ("button_slright", .l2), ("button_srright", .r2),
        ("button_home", .home), ("button_screenshot", .touchHardPress),
    ]

    /// A Pro Controller mapped to the DSU controller `pad`. The sticks are axes 0 and 1 (left) and 2 and
    /// 3 (right); the phone's tilt arrives as both Joy-Cons' motion.
    static func proControllerProfile(pad: Int, port: UInt16) -> String {
        profile(
            pad: pad,
            port: port,
            mappings: buttons.map { ($0.key, "button:\($0.button.rawValue)") } + [
                ("lstick", "axis_x:0,axis_y:1"), ("rstick", "axis_x:2,axis_y:3"),
                ("motionleft", "motion:0"), ("motionright", "motion:0"),
            ]
        )
    }

    /// Eden's controller type for a single right Joy-Con (`Settings::ControllerType::RightJoycon`). A
    /// profile may set it, unlike the other types.
    static let rightJoyConType = 3

    /// A right Joy-Con, as the phone's Joy-Con layouts send it: its A, B, X and Y as the phone's own
    /// (Cross, Circle, Square, Triangle), R and ZR as RB and RT, SL and SR as LB and LT, + as Menu, and
    /// the stick as the right stick, the Joy-Con's.
    static let joyConButtons: [(key: String, button: PadButton)] = [
        ("button_a", .cross), ("button_b", .circle), ("button_x", .square), ("button_y", .triangle),
        ("button_r", .r1), ("button_zr", .r2), ("button_slright", .l1), ("button_srright", .l2),
        ("button_plus", .options), ("button_home", .home), ("button_rstick", .r3),
    ]

    /// A single right Joy-Con mapped to the DSU controller `pad`. It has no left half, so Eden keeps its
    /// own defaults for those keys.
    static func joyConProfile(pad: Int, port: UInt16) -> String {
        profile(
            pad: pad,
            port: port,
            type: rightJoyConType,
            mappings: joyConButtons.map { ($0.key, "button:\($0.button.rawValue)") } + [
                ("rstick", "axis_x:2,axis_y:3"), ("motionleft", "motion:0"), ("motionright", "motion:0"),
            ]
        )
    }

    /// A profile in the format Eden saves them in, mapping each key to an input of the DSU controller `pad`.
    private static func profile(pad: Int, port: UInt16, type: Int? = nil, mappings: [(key: String, parameters: String)]) -> String {
        let device = "engine:cemuhookudp,guid:\(hostGUID),port:\(port),pad:\(pad)"
        var lines = ["[\(section)]"]
        if let type {
            lines += ["type\\default=false", "type=\(type)"]
        }
        for (key, parameters) in mappings {
            lines += ["\(key)\\default=false", "\(key)=\"\(device),\(parameters)\""]
        }
        return lines.map { $0 + "\n" }.joined()
    }
}
