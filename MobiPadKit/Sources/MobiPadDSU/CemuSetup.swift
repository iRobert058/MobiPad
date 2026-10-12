import Foundation

/// Sets Cemu (a Wii U emulator) up for MobiPad, so players don't have to map every button by hand (UX-01).
///
/// Writes controller profiles per player that players load in Cemu's input settings: a Wii U GamePad
/// ("MobiPad GamePad Player 1" to 4), for the phone's GamePad layout, a Wii U Pro Controller
/// ("MobiPad Pro Controller Player 1" to 4), for the Classic Controller layout, and a Wii Remote
/// ("MobiPad Wii Remote Player 1" to 4), for either Wii Remote layout. It never changes a
/// player's current mapping (`controller0.xml` to `controller3.xml`), so it doesn't matter whether Cemu
/// is running.
///
/// The format comes from Cemu's source (`InputManager.cpp`): one `emulated_controller` per file, with a
/// `controller` that reads the DSU pad, and `mappings` from Cemu's button numbers to DSU inputs.
public enum CemuSetup {
    public enum Outcome: Equatable, Sendable {
        case installed(profileNames: [String])
        /// There's no settings folder until Cemu has been opened once.
        case cemuNotFound
    }

    /// Where Cemu keeps its settings on macOS.
    public static let defaultConfigDirectory = URL.homeDirectory
        .appending(path: "Library/Application Support/Cemu", directoryHint: .isDirectory)

    public static func install(configDirectory: URL = defaultConfigDirectory, port: UInt16 = DSU.defaultPort) throws -> Outcome {
        guard FileManager.default.fileExists(atPath: configDirectory.path(percentEncoded: false)) else {
            return .cemuNotFound
        }
        let profileDirectory = configDirectory.appending(path: "controllerProfiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        var profileNames: [String] = []
        for kind in ProfileKind.allCases {
            for slot in 0..<DSU.slotCount {
                let name = kind.profileName(slot: slot)
                try kind.profile(name: name, pad: slot, port: port)
                    .write(to: profileDirectory.appending(path: "\(name).xml"), atomically: true, encoding: .utf8)
                profileNames.append(name)
            }
        }
        return .installed(profileNames: profileNames)
    }

    enum ProfileKind: CaseIterable {
        case gamePad
        case proController
        case wiiRemote

        func profileName(slot: Int) -> String {
            switch self {
            case .gamePad: "MobiPad GamePad Player \(slot + 1)"
            case .proController: "MobiPad Pro Controller Player \(slot + 1)"
            case .wiiRemote: "MobiPad Wii Remote Player \(slot + 1)"
            }
        }

        /// Cemu's name for the emulated controller (`EmulatedController::type_to_string`).
        var typeName: String {
            switch self {
            case .gamePad: "Wii U GamePad"
            case .proController: "Wii U Pro Controller"
            case .wiiRemote: "Wiimote"
            }
        }

        var mappings: [(button: Int, input: DSUInput)] {
            switch self {
            case .gamePad: gamePadMappings.map { ($0.button.rawValue, $0.input) }
            case .proController: proControllerMappings.map { ($0.button.rawValue, $0.input) }
            case .wiiRemote: wiiRemoteMappings.map { ($0.button.rawValue, $0.input) }
            }
        }

        /// A Wii Remote without a Nunchuk or other extension (`kWAPDevCore`), saved by `WiimoteController::save`.
        var extraSettings: String {
            self == .wiiRemote ? "\t<device_type>0</device_type>\n" : ""
        }

        func profile(name: String, pad: Int, port: UInt16) -> String {
            CemuSetup.profile(name: name, type: typeName, extraSettings: extraSettings, pad: pad, port: port, mappings: mappings)
        }
    }

    /// Cemu's numbers for the inputs of a DSU controller (`Buttons2` in `Controller.h`): bit n of the two
    /// DSU button bytes is button n, then ZL, ZR and the D-pad, then the stick axes, positive then negative.
    enum DSUInput: Int {
        case share = 0, l3, r3, options, up, right, down, left
        case l2, r2, l1, r1, triangle, circle, cross, square
        case leftStickRight = 38, leftStickUp, rightStickRight, rightStickUp
        case leftStickLeft = 44, leftStickDown, rightStickLeft, rightStickDown
    }

    /// The GamePad's buttons (`VPADController::ButtonId`), counted from 1.
    enum GamePadButton: Int {
        case a = 1, b, x, y, l, r, zl, zr, plus, minus, up, down, left, right, stickL, stickR
        case stickLUp, stickLDown, stickLLeft, stickLRight, stickRUp, stickRDown, stickRLeft, stickRRight
    }

    /// The Pro Controller's buttons (`ProController::ButtonId`): as the GamePad's, with Home after −.
    enum ProControllerButton: Int {
        case a = 1, b, x, y, l, r, zl, zr, plus, minus, home, up, down, left, right, stickL, stickR
        case stickLUp, stickLDown, stickLLeft, stickLRight, stickRUp, stickRDown, stickRLeft, stickRRight
    }

    /// The Wii Remote's buttons (`WiimoteController::ButtonId`), counted from 1.
    enum WiiRemoteButton: Int {
        case a = 1, b, one, two, nunchukZ, nunchukC, plus, minus, up, down, left, right
        case nunchukUp, nunchukDown, nunchukLeft, nunchukRight, home
    }

    /// The buttons as the phone's Wii Remote layouts send them, the same as for Dolphin: A as Cross, B as
    /// Circle, 1 as Square, 2 as Triangle, − as Share, + as Options, and the D-pad already turned for
    /// holding it sideways. Home has no mapping, as Cemu doesn't read it. The pointer needs none either:
    /// Cemu takes it from the DSU touch point, which the pointing layout fills in.
    static let wiiRemoteMappings: [(button: WiiRemoteButton, input: DSUInput)] = [
        (.a, .cross), (.b, .circle), (.one, .square), (.two, .triangle), (.plus, .options), (.minus, .share),
        (.up, .up), (.down, .down), (.left, .left), (.right, .right),
    ]

    /// By position, as on a Wii U: the right face button is A (the phone's B, sent as Circle) and the
    /// bottom one is B (the phone's A, Cross). Triggers are ZL and ZR. Cemu doesn't read the DSU Home
    /// byte, so Home has no mapping.
    static let gamePadMappings: [(button: GamePadButton, input: DSUInput)] = [
        (.a, .circle), (.b, .cross), (.x, .triangle), (.y, .square),
        (.l, .l1), (.r, .r1), (.zl, .l2), (.zr, .r2), (.plus, .options), (.minus, .share),
        (.up, .up), (.down, .down), (.left, .left), (.right, .right), (.stickL, .l3), (.stickR, .r3),
        (.stickLUp, .leftStickUp), (.stickLDown, .leftStickDown), (.stickLLeft, .leftStickLeft), (.stickLRight, .leftStickRight),
        (.stickRUp, .rightStickUp), (.stickRDown, .rightStickDown), (.stickRLeft, .rightStickLeft), (.stickRRight, .rightStickRight),
    ]

    static let proControllerMappings: [(button: ProControllerButton, input: DSUInput)] = [
        (.a, .circle), (.b, .cross), (.x, .triangle), (.y, .square),
        (.l, .l1), (.r, .r1), (.zl, .l2), (.zr, .r2), (.plus, .options), (.minus, .share),
        (.up, .up), (.down, .down), (.left, .left), (.right, .right), (.stickL, .l3), (.stickR, .r3),
        (.stickLUp, .leftStickUp), (.stickLDown, .leftStickDown), (.stickLLeft, .leftStickLeft), (.stickLRight, .leftStickRight),
        (.stickRUp, .rightStickUp), (.stickRDown, .rightStickDown), (.stickRLeft, .rightStickLeft), (.stickRRight, .rightStickRight),
    ]

    /// A profile in the format Cemu saves them in, reading DSU pad `pad` with motion on. The touchscreen
    /// needs no mapping: Cemu takes the GamePad's touch from the DSU touch point on its own.
    static func profile(
        name: String, type: String, extraSettings: String = "", pad: Int, port: UInt16, mappings: [(button: Int, input: DSUInput)]
    ) -> String {
        let entries = mappings.map { mapping in
            """
            \t\t\t<entry>
            \t\t\t\t<mapping>\(mapping.button)</mapping>
            \t\t\t\t<button>\(mapping.input.rawValue)</button>
            \t\t\t</entry>

            """
        }.joined()
        let deadzones = ["axis", "rotation", "trigger"].map { kind in
            "\t\t<\(kind)>\n\t\t\t<deadzone>0.25</deadzone>\n\t\t\t<range>1</range>\n\t\t</\(kind)>\n"
        }.joined()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <emulated_controller>
            \t<type>\(type)</type>
            \t<profile>\(name)</profile>

            """ + extraSettings + """
            \t<controller>
            \t\t<api>DSUController</api>
            \t\t<uuid>\(pad)</uuid>
            \t\t<display_name>Controller \(pad + 1)</display_name>
            \t\t<motion>true</motion>

            """ + deadzones + """
            \t\t<ip>127.0.0.1</ip>
            \t\t<port>\(port)</port>
            \t\t<mappings>

            """ + entries + """
            \t\t</mappings>
            \t</controller>
            </emulated_controller>

            """
    }
}
