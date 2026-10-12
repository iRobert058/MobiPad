import Foundation
import Testing
@testable import MobiPadDSU

struct CemuSetupTests {
    /// A fresh Cemu settings folder in the temporary directory.
    private let config: URL

    init() throws {
        config = FileManager.default.temporaryDirectory.appending(path: "CemuSetupTests-\(UUID())/Cemu")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    }

    static let profileNames = (1...4).map { "MobiPad GamePad Player \($0)" }
        + (1...4).map { "MobiPad Pro Controller Player \($0)" }
        + (1...4).map { "MobiPad Wii Remote Player \($0)" }

    /// Reads a written profile as XML.
    private func profile(_ name: String) throws -> XMLElement {
        let url = config.appending(path: "controllerProfiles/\(name).xml")
        return try #require(try XMLDocument(contentsOf: url).rootElement())
    }

    private func value(_ path: String, in element: XMLElement) throws -> String? {
        try element.nodes(forXPath: path).first?.stringValue
    }

    /// Cemu's button number → DSU input, for every mapping in the profile.
    private func mappings(in element: XMLElement) throws -> [Int: Int] {
        let entries = try element.nodes(forXPath: "controller/mappings/entry")
        return try Dictionary(uniqueKeysWithValues: entries.map { entry in
            let entry = try #require(entry as? XMLElement)
            return (
                try #require(Int(value("mapping", in: entry) ?? "")),
                try #require(Int(value("button", in: entry) ?? ""))
            )
        })
    }

    @Test func writesAGamePadAndAProControllerProfilePerPlayer() throws {
        #expect(try CemuSetup.install(configDirectory: config) == .installed(profileNames: Self.profileNames))
        for slot in 0..<4 {
            let gamePad = try profile("MobiPad GamePad Player \(slot + 1)")
            #expect(gamePad.name == "emulated_controller")
            #expect(try value("type", in: gamePad) == "Wii U GamePad")
            #expect(try value("profile", in: gamePad) == "MobiPad GamePad Player \(slot + 1)")
            #expect(try value("controller/api", in: gamePad) == "DSUController")
            #expect(try value("controller/uuid", in: gamePad) == "\(slot)")
            #expect(try value("controller/ip", in: gamePad) == "127.0.0.1")
            #expect(try value("controller/port", in: gamePad) == "26760")
            #expect(try value("controller/motion", in: gamePad) == "true")

            let pro = try profile("MobiPad Pro Controller Player \(slot + 1)")
            #expect(try value("type", in: pro) == "Wii U Pro Controller")
            #expect(try value("controller/uuid", in: pro) == "\(slot)")
        }
    }

    /// The same mappings as the profiles written by hand on 2026-10-10, which Cemu loaded and kept.
    @Test func mapsTheButtonsLikeTheProfilesCemuAccepted() throws {
        _ = try CemuSetup.install(configDirectory: config)
        let acceptedGamePad = [
            24: 40, 23: 46, 22: 47, 21: 41, 20: 38, 19: 44, 18: 45, 17: 39, 16: 2, 15: 1, 14: 5, 13: 7,
            12: 6, 11: 4, 10: 0, 9: 3, 8: 9, 7: 8, 6: 11, 5: 10, 4: 15, 3: 12, 2: 14, 1: 13,
        ]
        let acceptedPro = [
            25: 40, 23: 47, 22: 41, 21: 38, 20: 44, 19: 45, 18: 39, 17: 2, 16: 1, 15: 5, 14: 7, 13: 6,
            10: 0, 9: 3, 8: 9, 7: 8, 6: 11, 5: 10, 4: 15, 3: 12, 2: 14, 12: 4, 24: 46, 1: 13,
        ]
        #expect(try mappings(in: profile("MobiPad GamePad Player 1")) == acceptedGamePad)
        #expect(try mappings(in: profile("MobiPad Pro Controller Player 1")) == acceptedPro)
    }

    /// The phone's Wii Remote buttons (A as Cross, B as Circle, 1 as Square, 2 as Triangle) on Cemu's Wii Remote.
    @Test func writesAWiiRemotePlus() throws {
        _ = try CemuSetup.install(configDirectory: config)
        let remote = try profile("MobiPad Wii Remote Player 3")
        #expect(try value("type", in: remote) == "Wiimote")
        #expect(try value("device_type", in: remote) == "5") // with MotionPlus, without a Nunchuk
        #expect(try value("controller/uuid", in: remote) == "2")
        #expect(try value("controller/motion", in: remote) == "true")
        #expect(try mappings(in: remote) == [
            1: 14, 2: 13, 3: 15, 4: 12, // A, B, 1, 2
            7: 3, 8: 0, // +, −
            9: 4, 10: 6, 11: 7, 12: 5, // up, down, left, right
        ])
    }

    @Test func leavesThePlayersCurrentMappingAlone() throws {
        let profiles = config.appending(path: "controllerProfiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        let current = profiles.appending(path: "controller0.xml")
        try "mine".write(to: current, atomically: true, encoding: .utf8)
        _ = try CemuSetup.install(configDirectory: config)
        #expect(try String(contentsOf: current, encoding: .utf8) == "mine")
    }

    @Test func usesTheGivenPort() throws {
        _ = try CemuSetup.install(configDirectory: config, port: 26999)
        #expect(try value("controller/port", in: profile("MobiPad GamePad Player 2")) == "26999")
    }

    @Test func needsCemuToHaveRunOnce() throws {
        let missing = config.appending(path: "nothing-here")
        #expect(try CemuSetup.install(configDirectory: missing) == .cemuNotFound)
    }
}
